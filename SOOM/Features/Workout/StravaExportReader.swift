import Foundation
import ZIPFoundation

struct StravaExportEntry: Equatable {
    let activityId: String?
    let activityType: String?
    let activityDate: String?
    let activityName: String?
    let filename: String?
    let data: Data?
    let elapsedTimeSeconds: TimeInterval?
    let distanceMeters: Double?
    var deviceName: String? = nil

    func withData(_ data: Data?) -> Self {
        Self(activityId: activityId, activityType: activityType, activityDate: activityDate,
             activityName: activityName, filename: filename, data: data,
             elapsedTimeSeconds: elapsedTimeSeconds, distanceMeters: distanceMeters, deviceName: deviceName)
    }
}

enum StravaExportReaderError: Error, Equatable {
    case emptyData
    case notAZipArchive
    case missingActivitiesCSV
    case malformedCSV(reason: String)
    case entryCountLimitExceeded(maximumEntries: Int)
    case fileTooLarge(filename: String, maximumBytes: Int)
    case archiveTooLarge(maximumBytes: Int)
    case csvTooLarge(maximumBytes: Int)
    case expansionLimitExceeded(maximumBytes: Int)
    case unsafePath
    case ambiguousManifest
    case corruptEntry
}

struct StravaExportReader {
    let maximumEntryCount: Int
    let maximumFileBytes: Int
    let maximumArchiveBytes: Int
    let maximumCSVBytes: Int
    let maximumExpandedBytes: Int

    init(maximumEntryCount: Int = 5_000, maximumFileBytes: Int = 20 * 1_024 * 1_024,
         maximumArchiveBytes: Int = 512 * 1_024 * 1_024,
         maximumCSVBytes: Int = 4 * 1_024 * 1_024,
         maximumExpandedBytes: Int = 256 * 1_024 * 1_024) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumFileBytes = maximumFileBytes
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumCSVBytes = maximumCSVBytes
        self.maximumExpandedBytes = maximumExpandedBytes
    }

    func open(_ zipData: Data) throws -> StravaExportArchive {
        guard !zipData.isEmpty else { throw StravaExportReaderError.emptyData }
        guard zipData.count <= maximumArchiveBytes else {
            throw StravaExportReaderError.archiveTooLarge(maximumBytes: maximumArchiveBytes)
        }
        let archive: Archive
        do { archive = try Archive(data: zipData, accessMode: .read) }
        catch { throw StravaExportReaderError.notAZipArchive }
        return try prepare(archive)
    }

    func open(url: URL) throws -> StravaExportArchive {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw StravaExportReaderError.notAZipArchive }
        guard let size = values.fileSize, size > 0 else { throw StravaExportReaderError.emptyData }
        guard size <= maximumArchiveBytes else {
            throw StravaExportReaderError.archiveTooLarge(maximumBytes: maximumArchiveBytes)
        }
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) }
        catch { throw StravaExportReaderError.notAZipArchive }
        return try prepare(archive)
    }

    // Compatibility helper for small reader tests. Production consumes one entry at a time.
    func readEntries(from zipData: Data) throws -> [StravaExportEntry] {
        let archive = try open(zipData)
        return try archive.entries.indices.map { try archive.readEntry(at: $0) }
    }

    private func prepare(_ archive: Archive) throws -> StravaExportArchive {
        try Task.checkCancellation()
        var manifests: [Entry] = []
        var paths = Set<String>()
        var pathBytes = 0
        var count = 0
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            pathBytes += entry.path.utf8.count
            guard entry.path.utf8.count <= 4_096, pathBytes <= 2 * 1_024 * 1_024 else {
                throw StravaExportReaderError.unsafePath
            }
            guard count <= maximumEntryCount * 4 + 100 else {
                throw StravaExportReaderError.entryCountLimitExceeded(maximumEntries: maximumEntryCount)
            }
            guard paths.insert(entry.path).inserted else { throw StravaExportReaderError.ambiguousManifest }
            if entry.path == "activities.csv" || entry.path.hasSuffix("/activities.csv") {
                guard entry.type == .file, Self.isSafePath(entry.path) else { throw StravaExportReaderError.unsafePath }
                manifests.append(entry)
            }
        }
        guard !manifests.isEmpty else { throw StravaExportReaderError.missingActivitiesCSV }
        guard manifests.count == 1, let manifest = manifests.first else { throw StravaExportReaderError.ambiguousManifest }
        guard manifest.uncompressedSize <= UInt64(max(0, maximumCSVBytes)) else {
            throw StravaExportReaderError.csvTooLarge(maximumBytes: maximumCSVBytes)
        }
        let csvData = try Self.extract(manifest, archive: archive, limit: maximumCSVBytes) {
            StravaExportReaderError.csvTooLarge(maximumBytes: maximumCSVBytes)
        }
        guard csvData.count <= maximumExpandedBytes else {
            throw StravaExportReaderError.expansionLimitExceeded(maximumBytes: maximumExpandedBytes)
        }
        var bytes = csvData
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw StravaExportReaderError.malformedCSV(reason: "CSV is not UTF-8")
        }
        let rows = try Self.parseCSV(text, maximumRows: maximumEntryCount)
        guard let header = rows.first, let filenameIndex = header.firstIndex(of: "Filename"),
              header.filter({ $0 == "Filename" }).count == 1 else {
            throw StravaExportReaderError.malformedCSV(reason: "Missing or ambiguous CSV columns")
        }
        func field(_ row: [String], _ name: String) -> String? {
            guard let index = header.lastIndex(of: name), index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        let entries = rows.dropFirst().map { row in
            StravaExportEntry(activityId: field(row, "Activity ID"), activityType: field(row, "Activity Type"),
                activityDate: field(row, "Activity Date"), activityName: field(row, "Activity Name"),
                filename: filenameIndex < row.count ? field(row, "Filename") : nil, data: nil,
                elapsedTimeSeconds: field(row, "Elapsed Time").flatMap(Double.init),
                distanceMeters: field(row, "Distance").flatMap(Double.init), deviceName: field(row, "Device"))
        }
        let prefix = String(manifest.path.dropLast("activities.csv".count))
        return StravaExportArchive(archive: archive, entries: entries, prefix: prefix,
            maximumFileBytes: maximumFileBytes, maximumExpandedBytes: maximumExpandedBytes,
            expandedBytes: csvData.count)
    }

    static func isSafePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." })
    }

    static func extract(_ entry: Entry, archive: Archive, limit: Int,
                        limitError: () -> StravaExportReaderError) throws -> Data {
        var data = Data()
        let checksum = try archive.extract(entry, bufferSize: 64 * 1_024) { chunk in
            try Task.checkCancellation()
            guard chunk.count <= limit - data.count else { throw limitError() }
            data.append(chunk)
        }
        guard data.count == entry.uncompressedSize, checksum == entry.checksum else {
            throw StravaExportReaderError.corruptEntry
        }
        return data
    }

    private static func parseCSV(_ text: String, maximumRows: Int) throws -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var sawAnyContent = false

        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]

            if insideQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        currentField.append("\"")
                        index += 2
                        continue
                    }
                    insideQuotes = false
                    index += 1
                    continue
                }
                currentField.append(character)
                index += 1
                continue
            }

            switch character {
            case "\"":
                insideQuotes = true
                sawAnyContent = true
                index += 1
            case ",":
                currentRow.append(currentField)
                currentField = ""
                sawAnyContent = true
                index += 1
            case "\r":
                index += 1
            case "\n":
                currentRow.append(currentField)
                currentField = ""
                if sawAnyContent || !currentRow.isEmpty {
                    rows.append(currentRow)
                    guard rows.count <= maximumRows + 1 else {
                        throw StravaExportReaderError.entryCountLimitExceeded(maximumEntries: maximumRows)
                    }
                }
                currentRow = []
                sawAnyContent = false
                index += 1
            default:
                currentField.append(character)
                sawAnyContent = true
                index += 1
            }
        }

        guard !insideQuotes else {
            throw StravaExportReaderError.malformedCSV(reason: "unterminated quoted field")
        }

        if sawAnyContent || !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        guard rows.count <= maximumRows + 1 else {
            throw StravaExportReaderError.entryCountLimitExceeded(maximumEntries: maximumRows)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

/// Holds only bounded CSV metadata. Activity bytes are extracted and released by the caller per row.
final class StravaExportArchive {
    let entries: [StravaExportEntry]
    private let archive: Archive
    private let prefix: String
    private let maximumFileBytes: Int
    private let maximumExpandedBytes: Int
    private(set) var expandedBytes: Int

    init(archive: Archive, entries: [StravaExportEntry], prefix: String, maximumFileBytes: Int,
         maximumExpandedBytes: Int, expandedBytes: Int) {
        self.archive = archive
        self.entries = entries
        self.prefix = prefix
        self.maximumFileBytes = maximumFileBytes
        self.maximumExpandedBytes = maximumExpandedBytes
        self.expandedBytes = expandedBytes
    }

    func chargeExpandedBytes(_ count: Int) throws {
        guard count >= 0, count <= maximumExpandedBytes - expandedBytes else {
            throw StravaExportReaderError.expansionLimitExceeded(maximumBytes: maximumExpandedBytes)
        }
        expandedBytes += count
    }

    func readEntry(at index: Int) throws -> StravaExportEntry {
        try Task.checkCancellation()
        let metadata = entries[index]
        guard let filename = metadata.filename else { return metadata }
        guard StravaExportReader.isSafePath(filename) else { throw StravaExportReaderError.unsafePath }
        guard let entry = archive[filename] ?? archive[prefix + filename], entry.type == .file else { return metadata }
        guard entry.uncompressedSize <= UInt64(max(0, maximumFileBytes)) else {
            throw StravaExportReaderError.fileTooLarge(filename: filename, maximumBytes: maximumFileBytes)
        }
        guard entry.uncompressedSize <= UInt64(max(0, maximumExpandedBytes - expandedBytes)) else {
            throw StravaExportReaderError.expansionLimitExceeded(maximumBytes: maximumExpandedBytes)
        }
        // Charge before extraction so corrupt entries cannot repeatedly bypass the cumulative budget.
        expandedBytes += Int(entry.uncompressedSize)
        let data = try StravaExportReader.extract(entry, archive: archive, limit: maximumFileBytes) {
            StravaExportReaderError.fileTooLarge(filename: filename, maximumBytes: maximumFileBytes)
        }
        return metadata.withData(data)
    }
}
