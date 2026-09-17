import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
private final class StubDestination: ExportDestinationProviding {
    var url: URL?
    var requestedNames: [String] = []
    init(_ url: URL?) { self.url = url }
    func chooseDestination(suggestedName: String) async -> URL? {
        requestedNames.append(suggestedName)
        return url
    }
}

private struct FailingWriter: ExportFileWriting {
    let error: Error
    func write(_ data: Data, to url: URL) throws { throw error }
}

private final class CapturingWriter: ExportFileWriting, @unchecked Sendable {
    var written: [(Data, URL)] = []
    func write(_ data: Data, to url: URL) throws { written.append((data, url)) }
}

@MainActor
@Suite("Excel export")
struct WorkLogExportTests {
    /// UTC keeps serial numbers exact regardless of the test machine's zone.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Finishes a real session through the engine so exported data matches recorded work.
    @discardableResult
    func record(_ env: TestEnvironment, _ template: WorkTemplate, start: Date, minutes: Double, pauseMinutes: Double = 0, note: String = "") async throws -> WorkSession {
        env.clock.now = start
        let session = try env.sessionService.start(template: template)
        if pauseMinutes > 0 {
            env.clock.advance(minutes: 10)
            try env.sessionService.pause()
            env.clock.advance(minutes: pauseMinutes)
            try env.sessionService.resume()
            env.clock.advance(minutes: minutes - 10 - pauseMinutes)
        } else {
            env.clock.advance(minutes: minutes)
        }
        if !note.isEmpty { try env.sessionService.appendNote(note) }
        try await env.sessionService.finish()
        return session
    }

    func service(_ env: TestEnvironment, writer: ExportFileWriting = AtomicFileWriter()) -> WorkLogExportService {
        let calendarService = env.calendarService
        return WorkLogExportService(persistence: env.persistence, calendarName: { calendarService.calendar(withIdentifier: $0)?.title },
                                    writer: writer, calendar: Self.utc, now: { env.clock.now })
    }

    @Test("Workbook is a valid package with Work Logs and Summary sheets")
    func workbookStructure() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work")
        try await record(env, template, start: date(2026, 9, 15, 10), minutes: 144, pauseMinutes: 25)
        let data = try service(env).workbookData(scope: .all, filter: nil, includesSummary: true).data

        let reader = try XLSXReader(data)
        for part in ["[Content_Types].xml", "_rels/.rels", "docProps/app.xml", "docProps/core.xml", "xl/workbook.xml",
                     "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"] {
            #expect(reader.entries[part] != nil, "missing \(part)")
        }
        #expect(reader.allPartsAreWellFormed())
        #expect(try reader.sheetNames() == ["Work Logs", "Summary"])
        #expect(try reader.xml("[Content_Types].xml").contains("spreadsheetml.sheet.main+xml"))
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))

        let withoutSummary = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, includesSummary: false).data)
        #expect(try withoutSummary.sheetNames() == ["Work Logs"])
    }

    @Test("Rows contain the recorded dates, durations, template, tags, notes, and Calendar status")
    func rowContents() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work", priority: TaskPriority(isImportant: true))
        let session = try await record(env, template, start: date(2026, 9, 15, 10), minutes: 144, pauseMinutes: 25, note: "Fixed <timer> & drift")
        let reader = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, includesSummary: false).data)
        let cells = try reader.cells(sheet: 1)

        let headers = (0..<16).map { cells[XLSXWriter.columnName($0) + "1"]?.value }
        #expect(headers == ["Date", "Start Time", "End Time", "Duration", "Active Duration", "Paused Duration", "Template",
                            "Category", "Urgent", "Important", "Tags", "Notes", "Calendar", "Calendar Event Status",
                            "Calendar Event Identifier", "Session Status"])
        #expect(cells["A1"]?.style == SpreadsheetStyle.header.rawValue)

        // 2026-09-15 is serial 46280. 10:00 is 46280 + 10/24; 12:24 is 46280 + 744/1440.
        #expect(cells["A2"]?.value == "46280")
        #expect(cells["A2"]?.style == SpreadsheetStyle.date.rawValue)
        #expect(abs(Double(cells["B2"]!.value)! - (46280 + 10.0 / 24)) < 1e-9)
        #expect(abs(Double(cells["C2"]!.value)! - (46280 + 744.0 / 1440)) < 1e-9)
        #expect(cells["B2"]?.style == SpreadsheetStyle.dateTime.rawValue)
        // Durations are fractions of a day: 2h 24m wall clock, 1h 59m active, 25m paused.
        #expect(abs(Double(cells["D2"]!.value)! - 144.0 / 1440) < 1e-9)
        #expect(abs(Double(cells["E2"]!.value)! - 119.0 / 1440) < 1e-9)
        #expect(abs(Double(cells["F2"]!.value)! - 25.0 / 1440) < 1e-9)
        #expect(cells["D2"]?.style == SpreadsheetStyle.duration.rawValue)
        #expect(cells["G2"]?.value == "Software Engineering")
        #expect(cells["G2"]?.type == "inlineStr")
        #expect(cells["H2"]?.value == "Development")
        #expect(cells["I2"]?.value == "No")
        #expect(cells["J2"]?.value == "Yes")
        #expect(cells["K2"]?.value == "#coding #development")
        #expect(cells["L2"]?.value.contains("Fixed <timer> & drift") == true)
        #expect(cells["M2"]?.value == "Work")
        #expect(cells["N2"]?.value == "In Calendar")
        #expect(cells["O2"]?.value == session.calendarEventIdentifier)
        #expect(cells["P2"]?.value == "Completed")
        // Internal identifiers aren't exported.
        #expect(!(try reader.xml("xl/worksheets/sheet1.xml")).contains(session.id.uuidString))
    }

    @Test("Summary totals by template, day, and week")
    func summary() async throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate()
        let study = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"])
        try await record(env, engineering, start: date(2026, 9, 14, 9), minutes: 60)
        try await record(env, engineering, start: date(2026, 9, 15, 9), minutes: 90, pauseMinutes: 30)
        try await record(env, study, start: date(2026, 9, 15, 14), minutes: 30)
        let reader = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, includesSummary: true).data)
        let cells = try reader.cells(sheet: 2)
        let values = cells.mapValues(\.value)
        func row(labeled label: String) -> Int? {
            values.first { $0.key.hasPrefix("A") && $0.value == label }.flatMap { Int($0.key.dropFirst()) }
        }
        func minutes(_ reference: String) -> Double { (Double(values[reference] ?? "") ?? -1) * 1440 }

        #expect(values["B2"] == "All Work Logs")
        #expect(values["B4"] == "3")
        let total = try #require(row(labeled: "Total Work"))
        #expect(abs(minutes("B\(total)") - 180) < 1e-6)
        #expect(abs(minutes("B\(total + 1)") - 150) < 1e-6)
        #expect(abs(minutes("B\(total + 2)") - 30) < 1e-6)

        let byTemplate = try #require(row(labeled: "Work by Template"))
        #expect(values["A\(byTemplate + 1)"] == "Software Engineering")
        #expect(values["B\(byTemplate + 1)"] == "2")
        #expect(abs(minutes("C\(byTemplate + 1)") - 120) < 1e-6)
        #expect(abs(Double(values["D\(byTemplate + 1)"]!)! - 0.8) < 1e-9)
        #expect(cells["D\(byTemplate + 1)"]?.style == SpreadsheetStyle.percent.rawValue)
        #expect(values["A\(byTemplate + 2)"] == "Study")

        let daily = try #require(row(labeled: "Daily Totals"))
        #expect(values["A\(daily + 1)"] == "46279")   // 2026-09-14
        #expect(values["A\(daily + 2)"] == "46280")   // 2026-09-15
        #expect(values["B\(daily + 2)"] == "2")
        #expect(abs(minutes("D\(daily + 2)") - 90) < 1e-6)

        let weekly = try #require(row(labeled: "Weekly Totals (week starting)"))
        #expect(values["B\(weekly + 1)"] == "3")
        #expect(abs(minutes("D\(weekly + 1)") - 150) < 1e-6)
    }

    @Test("Scopes: all, today, this week, this month, and the current filter")
    func scopes() async throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate()
        let study = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"])
        try await record(env, engineering, start: date(2026, 8, 20, 9), minutes: 30)   // last month
        try await record(env, study, start: date(2026, 9, 2, 9), minutes: 30)          // this month, earlier week
        try await record(env, engineering, start: date(2026, 9, 14, 9), minutes: 30)   // this week
        try await record(env, study, start: date(2026, 9, 16, 9), minutes: 30)         // today
        // An open session and a cancelled one are never exported.
        env.clock.now = date(2026, 9, 16, 11)
        try env.sessionService.start(template: engineering)
        try env.sessionService.cancel()
        try env.sessionService.start(template: engineering)
        env.clock.now = date(2026, 9, 16, 12)

        let exporter = service(env)
        #expect(try exporter.records(scope: .all, filter: nil).count == 4)
        #expect(try exporter.records(scope: .today, filter: nil).map(\.log.templateName) == ["Study"])
        #expect(try exporter.records(scope: .thisWeek, filter: nil).count == 2)
        #expect(try exporter.records(scope: .thisMonth, filter: nil).count == 3)
        let filter = WorkLogFilter(templateID: study.id)
        #expect(try exporter.records(scope: .currentFilter, filter: filter).map(\.log.startedAt) == [date(2026, 9, 2, 9), date(2026, 9, 16, 9)])
        #expect(try exporter.records(scope: .all, filter: nil).map(\.log.startedAt) == [date(2026, 8, 20, 9), date(2026, 9, 2, 9), date(2026, 9, 14, 9), date(2026, 9, 16, 9)])
        #expect(WorkLogExportScope.available(filterIsActive: false) == [.all, .today, .thisWeek, .thisMonth])
        #expect(WorkLogExportScope.available(filterIsActive: true).contains(.currentFilter))
    }

    @Test("An empty export still produces a valid workbook with headers")
    func emptyExport() throws {
        let env = try TestEnvironment()
        let result = try service(env).workbookData(scope: .all, filter: nil, includesSummary: true)
        #expect(result.count == 0)
        let reader = try XLSXReader(result.data)
        #expect(reader.allPartsAreWellFormed())
        let cells = try reader.cells(sheet: 1)
        #expect(cells["A1"]?.value == "Date")
        #expect(cells["A2"] == nil)
        #expect(try reader.cells(sheet: 2)["B4"]?.value == "0")
        // No filter on an empty sheet (Excel rejects a one-row filter range here).
        #expect(!(try reader.xml("xl/worksheets/sheet1.xml")).contains("autoFilter"))
    }

    @Test("A large export stays valid and complete")
    func largeExport() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        let context = env.persistence.context
        let start = date(2025, 1, 1, 8)
        for index in 0..<5_000 {
            let begin = start.addingTimeInterval(Double(index) * 3 * 3600)
            let session = WorkSession(templateID: template.id, templateName: template.name, templateIcon: template.icon,
                                      templateColorHex: template.colorHex, startedAt: begin, tags: ["bulk"], notes: "Session \(index)")
            session.endedAt = begin.addingTimeInterval(45 * 60)
            session.state = .completed
            context.insert(session)
        }
        try env.persistence.save()
        env.clock.now = date(2026, 9, 16)

        let clock = ContinuousClock()
        var result: (data: Data, count: Int)?
        let elapsed = try clock.measure { result = try service(env).workbookData(scope: .all, filter: nil, includesSummary: true) }
        let output = try #require(result)
        #expect(output.count == 5_000)
        #expect(elapsed < .seconds(20))
        let reader = try XLSXReader(output.data)
        let cells = try reader.cells(sheet: 1)
        #expect(cells["G5001"]?.value == "Software Engineering")
        #expect(cells["L5001"]?.value == "Session 4999")
        #expect(cells["A5002"] == nil)
        #expect(try reader.xml("xl/worksheets/sheet1.xml").contains(#"<autoFilter ref="A1:P5001"/>"#))
    }

    @Test("Cancelling the Save panel writes nothing")
    func cancellation() async throws {
        let env = try TestEnvironment()
        try await record(env, try env.makeTemplate(), start: date(2026, 9, 15, 9), minutes: 30)
        let writer = CapturingWriter()
        let destination = StubDestination(nil)
        let outcome = await service(env, writer: writer).export(scope: .all, filter: nil, includesSummary: true, destination: destination)
        #expect(outcome == .cancelled)
        #expect(writer.written.isEmpty)
        #expect(destination.requestedNames.first?.hasSuffix(".xlsx") == true)
    }

    @Test("Export writes the file, adds the extension, and never changes work logs")
    func successfulExport() async throws {
        let env = try TestEnvironment()
        let session = try await record(env, try env.makeTemplate(), start: date(2026, 9, 15, 9), minutes: 30, note: "Keep me")
        let before = (session.notes, session.startedAt, session.endedAt, session.modifiedAt, session.calendarSyncStatus)
        let directory = FileManager.default.temporaryDirectory.appending(path: "ctl-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outcome = await service(env).export(scope: .all, filter: nil, includesSummary: true,
                                                destination: StubDestination(directory.appending(path: "Report")))
        let url = directory.appending(path: "Report.xlsx")
        #expect(outcome == .exported(url: url, sessionCount: 1))
        let reader = try XLSXReader(try Data(contentsOf: url))
        #expect(try reader.cells(sheet: 1)["L2"]?.value.contains("Keep me") == true)
        #expect((session.notes, session.startedAt, session.endedAt, session.modifiedAt, session.calendarSyncStatus) == before)
        #expect(try env.persistence.completedSessions().count == 1)
    }

    @Test("Write failures are reported with a specific, recoverable error")
    func writeFailures() async throws {
        let env = try TestEnvironment()
        try await record(env, try env.makeTemplate(), start: date(2026, 9, 15, 9), minutes: 30)
        let url = URL(filePath: "/tmp/Work Logs.xlsx")
        func outcome(_ error: Error) async -> WorkLogExportOutcome {
            await service(env, writer: FailingWriter(error: error)).export(scope: .all, filter: nil, includesSummary: false, destination: StubDestination(url))
        }
        #expect(await outcome(CocoaError(.fileWriteNoPermission)) == .failed(.permissionDenied("Work Logs.xlsx")))
        #expect(await outcome(CocoaError(.fileWriteOutOfSpace)) == .failed(.diskFull))
        #expect(await outcome(POSIXError(.EACCES)) == .failed(.permissionDenied("Work Logs.xlsx")))
        if case .failed(.writeFailed) = await outcome(CocoaError(.fileWriteUnknown)) {} else { Issue.record("expected writeFailed") }

        // A real write into a missing directory fails without creating anything.
        let missing = FileManager.default.temporaryDirectory.appending(path: "ctl-missing-\(UUID().uuidString)/Export.xlsx")
        let real = await service(env).export(scope: .all, filter: nil, includesSummary: false, destination: StubDestination(missing))
        if case .failed = real {} else { Issue.record("expected failure, got \(real)") }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(WorkLogExportError.diskFull.recoverySuggestion != nil)
        #expect(try env.persistence.completedSessions().count == 1)
    }

    @Test("Text is escaped, invalid XML characters removed, and oversized cells clipped")
    func textSafety() throws {
        #expect(XLSXWriter.escape(#"a & b < c > "d""#) == "a &amp; b &lt; c &gt; &quot;d&quot;")
        #expect(XLSXWriter.escape("tab\tline\nbell\u{07}end") == "tab\tline\nbellend")
        #expect(XLSXWriter.columnName(0) == "A")
        #expect(XLSXWriter.columnName(25) == "Z")
        #expect(XLSXWriter.columnName(26) == "AA")
        #expect(XLSXWriter.columnName(701) == "ZZ")
        #expect(XLSXWriter.uniqueSheetNames(["Work Logs", "work logs", "a/b:c", "", String(repeating: "x", count: 40)])
                == ["Work Logs", "work logs 2", "abc", "Sheet4", String(repeating: "x", count: 31)])
        #expect(XLSXWriter.format(0.5) == "0.5")
        #expect(XLSXWriter.format(46280) == "46280")

        let long = String(repeating: "n", count: 40_000)
        let workbook = SpreadsheetWorkbook(sheets: [SpreadsheetSheet(name: "S", rows: [[.text(long), .text("emoji 💻 ok")]])])
        let reader = try XLSXReader(try XLSXWriter(timeZone: TimeZone(identifier: "UTC")!).data(for: workbook))
        let cells = try reader.cells(sheet: 1)
        #expect(cells["A1"]?.value.count == XLSXWriter.maximumCellLength)
        #expect(cells["B1"]?.value == "emoji 💻 ok")
    }

    @Test("Invalid values are rejected instead of producing a corrupt file")
    func invalidData() {
        let writer = XLSXWriter(timeZone: TimeZone(identifier: "UTC")!)
        #expect(throws: XLSXWriterError.noSheets) { try writer.data(for: SpreadsheetWorkbook(sheets: [])) }
        #expect(throws: XLSXWriterError.invalidNumber(sheet: "S", cell: "A1")) {
            try writer.data(for: SpreadsheetWorkbook(sheets: [SpreadsheetSheet(name: "S", rows: [[.number(.nan)]])]))
        }
        #expect(throws: XLSXWriterError.dateOutOfRange(sheet: "S", cell: "B1")) {
            try writer.data(for: SpreadsheetWorkbook(sheets: [SpreadsheetSheet(name: "S", rows: [[.empty, .date(Date(timeIntervalSince1970: -3_000_000_000))]])]))
        }
    }

    @Test("Date serials follow the workbook time zone")
    func timeZones() {
        let date = date(2026, 9, 15, 22, 30)
        #expect(abs(XLSXWriter(timeZone: TimeZone(identifier: "UTC")!).serial(for: date) - (46280 + 22.5 / 24)) < 1e-9)
        // 22:30 UTC is 04:00 the next day in India (UTC+5:30).
        #expect(abs(XLSXWriter(timeZone: TimeZone(identifier: "Asia/Kolkata")!).serial(for: date) - (46281 + 4.0 / 24)) < 1e-9)
    }

    @Test("The suggested file name uses the local date, not UTC")
    func suggestedFileName() throws {
        let env = try TestEnvironment()
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        // 2026-09-15 19:36 UTC is 01:06 on 16 September in India.
        let instant = date(2026, 9, 15, 19, 36)
        let exporter = WorkLogExportService(persistence: env.persistence, calendarName: { _ in nil }, calendar: kolkata, now: { instant })
        #expect(exporter.suggestedFileName(scope: .all) == "Work Logs 2026-09-16.xlsx")
        #expect(exporter.suggestedFileName(scope: .thisWeek) == "Work Logs 2026-09-16 (This Week).xlsx")
    }

    @Test("CRC-32 matches the standard check value")
    func crc() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}
