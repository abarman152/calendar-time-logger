import Foundation

/// A cell value in a generated workbook. Dates and durations are stored as
/// real Excel serial numbers so they sort, filter, and sum in Excel.
public enum SpreadsheetCell: Hashable, Sendable {
    case empty
    case text(String, SpreadsheetStyle = .general)
    case number(Double, SpreadsheetStyle = .general)
    /// A point in time, written as an Excel date serial in the workbook's time zone.
    case date(Date, SpreadsheetStyle = .date)
    /// A length of time, written as a fraction of a day.
    case duration(TimeInterval, SpreadsheetStyle = .duration)
}

/// Cell formats defined in the workbook's `styles.xml`. The raw value is the
/// `cellXfs` index.
public enum SpreadsheetStyle: Int, Sendable, CaseIterable {
    case general = 0
    case header = 1
    case date = 2
    case dateTime = 3
    case duration = 4
    case percent = 5
    case bold = 6
    case title = 7
    case boldDuration = 8
    case integer = 9
    case time = 10
}

public struct SpreadsheetSheet: Hashable, Sendable {
    public var name: String
    /// Column widths in characters.
    public var columnWidths: [Double]
    public var rows: [[SpreadsheetCell]]
    /// Freezes the first row and adds filter buttons to it.
    public var hasHeaderRow: Bool

    public init(name: String, columnWidths: [Double] = [], rows: [[SpreadsheetCell]], hasHeaderRow: Bool = false) {
        self.name = name
        self.columnWidths = columnWidths
        self.rows = rows
        self.hasHeaderRow = hasHeaderRow
    }
}

public struct SpreadsheetWorkbook: Hashable, Sendable {
    public var sheets: [SpreadsheetSheet]
    public init(sheets: [SpreadsheetSheet]) { self.sheets = sheets }
}

public enum XLSXWriterError: Error, Equatable, Sendable {
    case noSheets
    case invalidNumber(sheet: String, cell: String)
    case dateOutOfRange(sheet: String, cell: String)
    case archiveFailed
}

/// Serializes a `SpreadsheetWorkbook` as an Office Open XML workbook (`.xlsx`,
/// ECMA-376 SpreadsheetML). Only the parts Excel, Numbers, and Quick Look
/// require are written: content types, relationships, document properties,
/// the workbook, styles, and one worksheet per sheet. Text uses inline strings.
public struct XLSXWriter: Sendable {
    public var timeZone: TimeZone
    public var generatedAt: Date

    /// Excel limits: 32,767 characters per cell, 31 per sheet name.
    public static let maximumCellLength = 32_767
    static let maximumSheetNameLength = 31

    public init(timeZone: TimeZone = .current, generatedAt: Date = Date()) {
        self.timeZone = timeZone
        self.generatedAt = generatedAt
    }

    public func data(for workbook: SpreadsheetWorkbook) throws -> Data {
        guard !workbook.sheets.isEmpty else { throw XLSXWriterError.noSheets }
        let names = Self.uniqueSheetNames(workbook.sheets.map(\.name))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var zip = ZipArchiveWriter(modificationDate: generatedAt, calendar: calendar)
        do {
            try zip.add(path: "[Content_Types].xml", data: Data(contentTypes(sheetCount: names.count).utf8))
            try zip.add(path: "_rels/.rels", data: Data(Self.rootRelationships.utf8))
            try zip.add(path: "docProps/app.xml", data: Data(appProperties(sheetNames: names).utf8))
            try zip.add(path: "docProps/core.xml", data: Data(coreProperties().utf8))
            try zip.add(path: "xl/workbook.xml", data: Data(workbookXML(workbook.sheets, names: names).utf8))
            try zip.add(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelationships(sheetCount: names.count).utf8))
            try zip.add(path: "xl/styles.xml", data: Data(Self.stylesXML.utf8))
            for (index, sheet) in workbook.sheets.enumerated() {
                let xml = try worksheetXML(sheet, name: names[index])
                try zip.add(path: "xl/worksheets/sheet\(index + 1).xml", data: Data(xml.utf8))
            }
            return try zip.finish()
        } catch let error as XLSXWriterError {
            throw error
        } catch {
            throw XLSXWriterError.archiveFailed
        }
    }

    // MARK: Values

    /// Excel's 1900 date system: serial 25569 is 1970-01-01 00:00 local time.
    func serial(for date: Date) -> Double {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return local / 86_400 + 25_569
    }

    /// `A`, `B`, … `Z`, `AA`, …
    static func columnName(_ index: Int) -> String {
        var number = index + 1
        var name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            number = (number - 1) / 26
        }
        return name
    }

    /// Escapes XML special characters and removes characters XML 1.0 forbids.
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            default:
                let value = scalar.value
                if value < 0x20 || value == 0xFFFE || value == 0xFFFF { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func uniqueSheetNames(_ names: [String]) -> [String] {
        let forbidden = CharacterSet(charactersIn: "[]:*?/\\")
        var used = Set<String>()
        return names.enumerated().map { index, raw in
            var name = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !forbidden.contains($0) }))
                .trimmingCharacters(in: CharacterSet(charactersIn: "' ").union(.whitespaces))
            if name.isEmpty { name = "Sheet\(index + 1)" }
            name = String(name.prefix(maximumSheetNameLength))
            var candidate = name
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                let tail = " \(suffix)"
                candidate = String(name.prefix(maximumSheetNameLength - tail.count)) + tail
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    // MARK: Parts

    private func worksheetXML(_ sheet: SpreadsheetSheet, name: String) throws -> String {
        let columnCount = max(sheet.columnWidths.count, sheet.rows.map(\.count).max() ?? 0)
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#
        if sheet.hasHeaderRow, sheet.rows.count > 1 {
            xml += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft"/></sheetView></sheetViews>"#
        } else {
            xml += #"<sheetViews><sheetView workbookViewId="0"/></sheetViews>"#
        }
        xml += #"<sheetFormatPr defaultRowHeight="15"/>"#
        if !sheet.columnWidths.isEmpty {
            xml += "<cols>"
            for (index, width) in sheet.columnWidths.enumerated() {
                xml += #"<col min="\#(index + 1)" max="\#(index + 1)" width="\#(Self.format(width))" customWidth="1"/>"#
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for (rowIndex, row) in sheet.rows.enumerated() {
            let rowNumber = rowIndex + 1
            xml += #"<row r="\#(rowNumber)">"#
            for (columnIndex, cell) in row.enumerated() {
                let reference = Self.columnName(columnIndex) + String(rowNumber)
                xml += try cellXML(cell, reference: reference, sheet: name)
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        if sheet.hasHeaderRow, sheet.rows.count > 1, columnCount > 0 {
            xml += #"<autoFilter ref="A1:\#(Self.columnName(columnCount - 1))\#(sheet.rows.count)"/>"#
        }
        xml += "</worksheet>"
        return xml
    }

    private func cellXML(_ cell: SpreadsheetCell, reference: String, sheet: String) throws -> String {
        switch cell {
        case .empty:
            return ""
        case .text(let text, let style):
            let clipped = text.count > Self.maximumCellLength ? String(text.prefix(Self.maximumCellLength)) : text
            return #"<c r="\#(reference)" t="inlineStr"\#(Self.styleAttribute(style))><is><t xml:space="preserve">\#(Self.escape(clipped))</t></is></c>"#
        case .number(let value, let style):
            guard value.isFinite else { throw XLSXWriterError.invalidNumber(sheet: sheet, cell: reference) }
            return #"<c r="\#(reference)"\#(Self.styleAttribute(style))><v>\#(Self.format(value))</v></c>"#
        case .date(let date, let style):
            let value = serial(for: date)
            // Excel's 1900 date system can't represent dates before 1900-03-01 correctly.
            guard value.isFinite, value >= 61, value < 2_958_466 else {
                throw XLSXWriterError.dateOutOfRange(sheet: sheet, cell: reference)
            }
            return #"<c r="\#(reference)"\#(Self.styleAttribute(style))><v>\#(Self.format(value))</v></c>"#
        case .duration(let interval, let style):
            guard interval.isFinite else { throw XLSXWriterError.invalidNumber(sheet: sheet, cell: reference) }
            return #"<c r="\#(reference)"\#(Self.styleAttribute(style))><v>\#(Self.format(max(0, interval) / 86_400))</v></c>"#
        }
    }

    private static func styleAttribute(_ style: SpreadsheetStyle) -> String {
        style == .general ? "" : #" s="\#(style.rawValue)""#
    }

    /// Locale-independent decimal with up to 10 fractional digits (enough for
    /// sub-millisecond precision in date serials).
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private func contentTypes(sheetCount: Int) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        xml += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        xml += #"<Default Extension="xml" ContentType="application/xml"/>"#
        xml += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        for index in 1...sheetCount {
            xml += #"<Override PartName="/xl/worksheets/sheet\#(index).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        xml += #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        xml += #"<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>"#
        xml += #"<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>"#
        xml += "</Types>"
        return xml
    }

    private static let rootRelationships = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
    """#

    private func appProperties(sheetNames: [String]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">"#
        xml += "<Application>Calendar Time Logger</Application>"
        xml += #"<TitlesOfParts><vt:vector size="\#(sheetNames.count)" baseType="lpstr">"#
        for name in sheetNames { xml += "<vt:lpstr>\(Self.escape(name))</vt:lpstr>" }
        xml += "</vt:vector></TitlesOfParts></Properties>"
        return xml
    }

    private func coreProperties() -> String {
        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">"#
        xml += "<dc:title>Work Logs</dc:title><dc:creator>Calendar Time Logger</dc:creator>"
        xml += #"<dcterms:created xsi:type="dcterms:W3CDTF">\#(timestamp)</dcterms:created>"#
        xml += #"<dcterms:modified xsi:type="dcterms:W3CDTF">\#(timestamp)</dcterms:modified>"#
        xml += "</cp:coreProperties>"
        return xml
    }

    private func workbookXML(_ sheets: [SpreadsheetSheet], names: [String]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#
        xml += #"<bookViews><workbookView/></bookViews><sheets>"#
        for (index, name) in names.enumerated() {
            xml += #"<sheet name="\#(Self.escape(name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }
        xml += "</sheets>"
        let filters = sheets.enumerated().filter { $0.element.hasHeaderRow && $0.element.rows.count > 1 }
        if !filters.isEmpty {
            xml += "<definedNames>"
            for (index, sheet) in filters {
                let columns = max(sheet.columnWidths.count, sheet.rows.map(\.count).max() ?? 1)
                let quoted = "'" + names[index].replacingOccurrences(of: "'", with: "''") + "'"
                let range = "\(quoted)!$A$1:$\(Self.columnName(columns - 1))$\(sheet.rows.count)"
                xml += #"<definedName name="_xlnm._FilterDatabase" localSheetId="\#(index)" hidden="1">\#(Self.escape(range))</definedName>"#
            }
            xml += "</definedNames>"
        }
        xml += "</workbook>"
        return xml
    }

    private func workbookRelationships(sheetCount: Int) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for index in 1...sheetCount {
            xml += #"<Relationship Id="rId\#(index)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(index).xml"/>"#
        }
        xml += #"<Relationship Id="rId\#(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        xml += "</Relationships>"
        return xml
    }

    /// `cellXfs` order must match `SpreadsheetStyle`.
    private static let stylesXML = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="4"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd h:mm AM/PM"/><numFmt numFmtId="166" formatCode="[h]:mm:ss"/><numFmt numFmtId="167" formatCode="h:mm AM/PM"/></numFmts><fonts count="3"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="14"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE9E6F2"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF8E8E93"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="11"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="9" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="166" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="167" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """#
}
