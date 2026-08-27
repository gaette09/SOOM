import Compression
import Foundation

enum GzipDecompressorError: Error, Equatable {
    case emptyData
    case notGzipFormat
    case truncatedHeader
    case unsupportedCompressionMethod
    case decompressionFailed
    case sizeMismatch
    case sizeLimitExceeded(maximumBytes: Int)
}

struct GzipDecompressor {
    let maximumDecompressedBytes: Int

    init(maximumDecompressedBytes: Int = 100 * 1_024 * 1_024) {
        self.maximumDecompressedBytes = maximumDecompressedBytes
    }

    // gzip (RFC 1952) wraps a raw DEFLATE (RFC 1951) stream in a 10-byte fixed
    // header, a set of optional fields controlled by the header's flag byte, and
    // an 8-byte trailer. Compression.framework's COMPRESSION_ZLIB algorithm only
    // decodes the raw DEFLATE body — it knows nothing about the gzip container —
    // so the container has to be parsed and stripped by hand before decoding.
    // Different encoders include different optional fields (Strava's export
    // pipeline may or may not set FNAME), so the header is walked field-by-field
    // rather than assumed to always be exactly 10 bytes.
    func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw GzipDecompressorError.emptyData }
        guard data.count >= 10 else { throw GzipDecompressorError.truncatedHeader }

        let bytes = [UInt8](data)
        guard bytes[0] == 0x1F, bytes[1] == 0x8B else {
            throw GzipDecompressorError.notGzipFormat
        }
        guard bytes[2] == 8 else {
            throw GzipDecompressorError.unsupportedCompressionMethod
        }

        let flags = bytes[3]
        var offset = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw GzipDecompressorError.truncatedHeader }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
            guard offset + extraLength <= bytes.count else { throw GzipDecompressorError.truncatedHeader }
            offset += extraLength
        }
        if flags & 0x08 != 0 { // FNAME
            offset = try Self.skipNulTerminatedField(bytes, from: offset)
        }
        if flags & 0x10 != 0 { // FCOMMENT
            offset = try Self.skipNulTerminatedField(bytes, from: offset)
        }
        if flags & 0x02 != 0 { // FHCRC
            guard offset + 2 <= bytes.count else { throw GzipDecompressorError.truncatedHeader }
            offset += 2
        }

        guard bytes.count - offset > 8 else {
            throw GzipDecompressorError.decompressionFailed
        }

        let trailerStart = bytes.count - 8
        let isize = (0..<4).reduce(UInt32(0)) { partial, index in
            partial | (UInt32(bytes[trailerStart + 4 + index]) << (8 * index))
        }

        guard Int(isize) <= maximumDecompressedBytes else {
            throw GzipDecompressorError.sizeLimitExceeded(maximumBytes: maximumDecompressedBytes)
        }

        let bodyRange = offset..<trailerStart
        guard bodyRange.lowerBound < bodyRange.upperBound else {
            throw GzipDecompressorError.decompressionFailed
        }
        let compressedBody = Array(bytes[bodyRange])

        let destinationCapacity = min(
            maximumDecompressedBytes,
            max(Int(isize), compressedBody.count * 20, 64)
        )
        guard destinationCapacity > 0 else {
            throw GzipDecompressorError.decompressionFailed
        }

        var destinationBuffer = [UInt8](repeating: 0, count: destinationCapacity)
        let decodedCount = destinationBuffer.withUnsafeMutableBytes { destination -> Int in
            compressedBody.withUnsafeBytes { source -> Int in
                guard
                    let destBase = destination.bindMemory(to: UInt8.self).baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                return compression_decode_buffer(
                    destBase, destinationCapacity,
                    sourceBase, compressedBody.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount > 0 else {
            throw GzipDecompressorError.decompressionFailed
        }

        return Data(destinationBuffer.prefix(decodedCount))
    }

    private static func skipNulTerminatedField(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while true {
            guard index < bytes.count else { throw GzipDecompressorError.truncatedHeader }
            if bytes[index] == 0 {
                return index + 1
            }
            index += 1
        }
    }
}
