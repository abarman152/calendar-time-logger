import Foundation
@testable import CalendarTimeLoggerKit

/// Reads back generated workbooks independently of the writer: parses the ZIP
/// central directory, verifies every entry's CRC, inflates entries, and
/// parses worksheets with `XMLParser`.
struct XLSXReader {
    struct Cell: Equatable {
        var type: String?
        var style: Int
        var value: String
    }

    let entries: [String: Data]

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        guard let eocd = stride(from: bytes.count - 22, through: 0, by: -1).first(where: { u32($0) == 0x0605_4B50 }) else {
            throw ReadError.notZip
        }
        let count = u16(eocd + 10)
        var offset = u32(eocd + 16)
        var entries: [String: Data] = [:]
        for _ in 0..<count {
            guard u32(offset) == 0x0201_4B50 else { throw ReadError.corrupt("central directory") }
            let method = u16(offset + 10)
            let crc = UInt32(u32(offset + 16))
            let compressed = u32(offset + 20)
            let size = u32(offset + 24)
            let nameLength = u16(offset + 28)
            let extra = u16(offset + 30)
            let comment = u16(offset + 32)
            let local = u32(offset + 42)
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            guard u32(local) == 0x0403_4B50 else { throw ReadError.corrupt("local header \(name)") }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let payload = Data(bytes[start..<(start + compressed)])
            let content: Data
            switch method {
            case 0: content = payload
            case 8: content = try (payload as NSData).decompressed(using: .zlib) as Data
            default: throw ReadError.corrupt("method \(method)")
            }
            guard content.count == size, CRC32.checksum(content) == crc else { throw ReadError.corrupt("crc \(name)") }
            entries[name] = content
            offset += 46 + nameLength + extra + comment
        }
        self.entries = entries
    }

    enum ReadError: Error { case notZip, corrupt(String), missing(String) }

    func xml(_ path: String) throws -> String {
        guard let data = entries[path] else { throw ReadError.missing(path) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether every part is well-formed XML.
    func allPartsAreWellFormed() -> Bool {
        entries.values.allSatisfy { XMLParser(data: $0).parse() }
    }

    /// Sheet names in workbook order.
    func sheetNames() throws -> [String] {
        let delegate = AttributeCollector(element: "sheet", attribute: "name")
        let parser = XMLParser(data: entries["xl/workbook.xml"] ?? Data())
        parser.delegate = delegate
        guard parser.parse() else { throw ReadError.corrupt("workbook.xml") }
        return delegate.values
    }

    /// Cells of sheet N (1-based), keyed by reference (`A1`).
    func cells(sheet index: Int) throws -> [String: Cell] {
        guard let data = entries["xl/worksheets/sheet\(index).xml"] else { throw ReadError.missing("sheet\(index)") }
        let delegate = CellCollector()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ReadError.corrupt("sheet\(index)") }
        return delegate.cells
    }

    private final class AttributeCollector: NSObject, XMLParserDelegate {
        let element: String
        let attribute: String
        var values: [String] = []
        init(element: String, attribute: String) {
            self.element = element
            self.attribute = attribute
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == element, let value = attributes[attribute] { values.append(value) }
        }
    }

    private final class CellCollector: NSObject, XMLParserDelegate {
        var cells: [String: Cell] = [:]
        private var reference: String?
        private var current: Cell?
        private var collecting = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "c":
                reference = attributes["r"]
                current = Cell(type: attributes["t"], style: Int(attributes["s"] ?? "0") ?? 0, value: "")
            case "v", "t":
                collecting = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if collecting { current?.value += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": collecting = false
            case "c":
                if let reference, let current { cells[reference] = current }
                reference = nil
                current = nil
            default: break
            }
        }
    }
}
