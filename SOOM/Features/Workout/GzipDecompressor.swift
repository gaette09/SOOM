import Foundation
import zlib

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

    /// Decode the complete gzip member, including CRC32 and size verification, in bounded chunks.
    /// A full output buffer is never mistaken for a complete stream. Trailing members/data are rejected.
    func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw GzipDecompressorError.emptyData }
        guard data.count >= 10 else { throw GzipDecompressorError.truncatedHeader }
        guard data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw GzipDecompressorError.notGzipFormat
        }
        guard data[data.startIndex + 2] == 8 else { throw GzipDecompressorError.unsupportedCompressionMethod }
        guard data.count <= Int(UInt32.max), maximumDecompressedBytes >= 0 else {
            throw GzipDecompressorError.decompressionFailed
        }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw GzipDecompressorError.decompressionFailed
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = UInt32(data.count)
            var output = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                try Task.checkCancellation()
                let inputBefore = stream.avail_in
                let status = buffer.withUnsafeMutableBytes { destination -> Int32 in
                    stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress!
                    stream.avail_out = UInt32(destination.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = buffer.count - Int(stream.avail_out)
                guard produced <= maximumDecompressedBytes - output.count else {
                    throw GzipDecompressorError.sizeLimitExceeded(maximumBytes: maximumDecompressedBytes)
                }
                output.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw GzipDecompressorError.sizeMismatch }
                    return output
                }
                guard status == Z_OK, produced > 0 || stream.avail_in < inputBefore else {
                    throw GzipDecompressorError.decompressionFailed
                }
            }
        }
    }
}
