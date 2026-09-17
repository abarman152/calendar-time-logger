import Foundation

/// Writes a ZIP archive (PKWARE APPNOTE 6.3), the container format of `.xlsx`.
///
/// Entries are DEFLATE-compressed with Foundation's zlib implementation, or
/// stored when compression doesn't help. ZIP64 isn't needed: workbooks are far
/// below the 4 GB limit, which `finish()` enforces.
struct ZipArchiveWriter {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let offset: Int
    }

    private var output = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(modificationDate: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: modificationDate)
        dosTime = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        dosDate = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
    }

    mutating func add(path: String, data: Data) throws {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(data)
        var method: UInt16 = 0
        var payload = data
        if let deflated = try? (data as NSData).compressed(using: .zlib) as Data, deflated.count < data.count {
            method = 8
            payload = deflated
        }
        entries.append(Entry(name: name, crc: crc, method: method, compressedSize: payload.count,
                             uncompressedSize: data.count, offset: output.count))
        output.appendUInt32(0x0403_4B50)
        output.appendUInt16(20)            // version needed to extract
        output.appendUInt16(0x0800)        // flags: UTF-8 names
        output.appendUInt16(method)
        output.appendUInt16(dosTime)
        output.appendUInt16(dosDate)
        output.appendUInt32(crc)
        output.appendUInt32(UInt32(payload.count))
        output.appendUInt32(UInt32(data.count))
        output.appendUInt16(UInt16(name.count))
        output.appendUInt16(0)             // extra field length
        output.append(name)
        output.append(payload)
        guard output.count < Int(UInt32.max) else { throw ZipArchiveError.archiveTooLarge }
    }

    mutating func finish() throws -> Data {
        let directoryOffset = output.count
        for entry in entries {
            output.appendUInt32(0x0201_4B50)
            output.appendUInt16(20)        // version made by
            output.appendUInt16(20)        // version needed
            output.appendUInt16(0x0800)
            output.appendUInt16(entry.method)
            output.appendUInt16(dosTime)
            output.appendUInt16(dosDate)
            output.appendUInt32(entry.crc)
            output.appendUInt32(UInt32(entry.compressedSize))
            output.appendUInt32(UInt32(entry.uncompressedSize))
            output.appendUInt16(UInt16(entry.name.count))
            output.appendUInt16(0)         // extra
            output.appendUInt16(0)         // comment
            output.appendUInt16(0)         // disk number
            output.appendUInt16(0)         // internal attributes
            output.appendUInt32(0)         // external attributes
            output.appendUInt32(UInt32(entry.offset))
            output.append(entry.name)
        }
        let directorySize = output.count - directoryOffset
        guard entries.count < Int(UInt16.max), output.count < Int(UInt32.max) else { throw ZipArchiveError.archiveTooLarge }
        output.appendUInt32(0x0605_4B50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(directorySize))
        output.appendUInt32(UInt32(directoryOffset))
        output.appendUInt16(0)
        return output
    }
}

enum ZipArchiveError: Error, Equatable {
    case archiveTooLarge
}

/// CRC-32 (ISO 3309 / ITU-T V.42), as required for ZIP entries.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
