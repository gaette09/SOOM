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
}

enum StravaExportReaderError: Error, Equatable {
    case emptyData
    case notAZipArchive
    case missingActivitiesCSV
    case malformedCSV(reason: String)
    case entryCountLimitExceeded(maximumEntries: Int)
    case fileTooLarge(filename: String, maximumBytes: Int)
}

struct StravaExportReader {
    let maximumEntryCount: Int
    let maximumFileBytes: Int

    init(maximumEntryCount: Int = 5_000, maximumFileBytes: Int = 20 * 1_024 * 1_024) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumFileBytes = maximumFileBytes
    }

    func readEntries(from zipData: Data) throws -> [StravaExportEntry] {
        guard !zipData.isEmpty else { throw StravaExportReaderError.emptyData }

        let archive: Archive
        do {
            archive = try Archive(data: zipData, accessMode: .read)
        } catch {
            throw StravaExportReaderError.notAZipArchive
        }

        guard let csvEntry = Self.locateActivitiesCSV(in: archive) else {
            throw StravaExportReaderError.missingActivitiesCSV
        }

        let csvData = try Self.extractData(csvEntry, from: archive)
        let csvText = Self.decodeStrippingBOM(csvData)
        let rows = try Self.parseCSV(csvText)

        guard let header = rows.first else {
            throw StravaExportReaderError.malformedCSV(reason: "CSV has no header row")
        }
        guard let filenameIndex = header.firstIndex(of: "Filename") else {
            throw StravaExportReaderError.malformedCSV(reason: "CSV header has no \"Filename\" column")
        }
        let activityIdIndex = header.firstIndex(of: "Activity ID")
        let activityTypeIndex = header.firstIndex(of: "Activity Type")
        let activityDateIndex = header.firstIndex(of: "Activity Date")
        let activityNameIndex = header.firstIndex(of: "Activity Name")
        let elapsedTimeIndex = header.firstIndex(of: "Elapsed Time")
        let distanceIndex = header.firstIndex(of: "Distance")

        let dataRows = rows.dropFirst()
        guard dataRows.count <= maximumEntryCount else {
            throw StravaExportReaderError.entryCountLimitExceeded(maximumEntries: maximumEntryCount)
        }

        return try dataRows.map { row in
            let filenameValue = Self.field(row, at: filenameIndex)
            let filename = (filenameValue?.isEmpty ?? true) ? nil : filenameValue

            var fileData: Data?
            if let filename {
                if let fileEntry = archive[filename], fileEntry.type == .file {
                    guard fileEntry.uncompressedSize <= UInt64(maximumFileBytes) else {
                        throw StravaExportReaderError.fileTooLarge(
                            filename: filename,
                            maximumBytes: maximumFileBytes
                        )
                    }
                    fileData = try Self.extractData(fileEntry, from: archive)
                } else {
                    fileData = nil
                }
            }

            return StravaExportEntry(
                activityId: Self.field(row, at: activityIdIndex),
                activityType: Self.field(row, at: activityTypeIndex),
                activityDate: Self.field(row, at: activityDateIndex),
                activityName: Self.field(row, at: activityNameIndex),
                filename: filename,
                data: fileData,
                elapsedTimeSeconds: Self.field(row, at: elapsedTimeIndex).flatMap(TimeInterval.init),
                distanceMeters: Self.field(row, at: distanceIndex).flatMap(Double.init)
            )
        }
    }

    private static func field(_ row: [String], at index: Int?) -> String? {
        guard let index, index < row.count else { return nil }
        return row[index]
    }

    private static func locateActivitiesCSV(in archive: Archive) -> Entry? {
        if let exact = archive["activities.csv"] {
            return exact
        }
        for entry in archive where entry.path.hasSuffix("/activities.csv") {
            return entry
        }
        return nil
    }

    private static func extractData(_ entry: Entry, from archive: Archive) throws -> Data {
        var collected = Data()
        _ = try archive.extract(entry) { chunk in
            collected.append(chunk)
        }
        return collected
    }

    private static func decodeStrippingBOM(_ data: Data) -> String {
        var bytes = data
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if bytes.count >= 3, Array(bytes.prefix(3)) == bom {
            bytes.removeFirst(3)
        }
        return String(data: bytes, encoding: .utf8) ?? ""
    }

    // Minimal RFC4180-style parser: comma-separated fields, optional double-quote
    // wrapping, doubled `""` inside a quoted field is a literal quote, and a
    // quoted field may itself contain commas or newlines (Strava activity names
    // routinely contain commas, so a naive split(separator: ",") silently
    // misaligns every column after the first comma in such a name).
    private static func parseCSV(_ text: String) throws -> [[String]] {
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

        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
