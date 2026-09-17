import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Excel export columns")
struct ExportColumnTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func service(_ env: TestEnvironment) -> WorkLogExportService {
        let calendarService = env.calendarService
        return WorkLogExportService(persistence: env.persistence, calendarName: { calendarService.calendar(withIdentifier: $0)?.title },
                                    calendar: Self.utc, now: { env.clock.now })
    }

    /// Records one finished session through the engine.
    @discardableResult
    func record(_ env: TestEnvironment, _ template: WorkTemplate, start: Date, minutes: Double) async throws -> WorkSession {
        env.clock.now = start
        let session = try env.sessionService.start(template: template)
        env.clock.advance(minutes: minutes)
        try await env.sessionService.finish()
        return session
    }

    @Test("Exporting Date, Template, Duration, Urgent, and Important writes exactly those columns")
    func priorityAnalysisExport() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work", priority: TaskPriority(isUrgent: false, isImportant: true))
        try await record(env, template, start: date(2026, 9, 16, 9), minutes: 84.62)

        let columns = WorkLogExportPreset.priorityAnalysis.selection
        let data = try service(env).workbookData(scope: .all, filter: nil, columns: columns, includesSummary: false).data
        let cells = try XLSXReader(data).cells(sheet: 1)

        #expect(cells["A1"]?.value == "Date")
        #expect(cells["B1"]?.value == "Template")
        #expect(cells["C1"]?.value == "Active Duration")
        #expect(cells["D1"]?.value == "Urgent")
        #expect(cells["E1"]?.value == "Important")
        // Nothing beyond the five chosen columns exists.
        #expect(cells["F1"] == nil)

        #expect(cells["A2"]?.value == "46281")                       // 2026-09-16
        #expect(cells["B2"]?.value == "Software Engineering")
        #expect(abs(Double(cells["C2"]!.value)! - 84.62 / 1440) < 1e-6)
        #expect(cells["D2"]?.value == "No")
        #expect(cells["E2"]?.value == "Yes")
        #expect(cells["F2"] == nil)

        // Unselected fields never leak into the sheet.
        let xml = try XLSXReader(data).xml("xl/worksheets/sheet1.xml")
        for absent in ["Notes", "Tags", "Calendar Event Identifier", "Session Status", "#coding"] {
            #expect(!xml.contains(absent), "unselected value \(absent) was exported")
        }
    }

    @Test("Column order follows the user's order")
    func columnOrder() async throws {
        let env = try TestEnvironment()
        try await record(env, try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: false)),
                         start: date(2026, 9, 16, 9), minutes: 30)
        let columns = WorkLogColumnSelection([.important, .urgent, .template, .date])
        let cells = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, columns: columns, includesSummary: false).data)
            .cells(sheet: 1)
        #expect((0..<4).map { cells[XLSXWriter.columnName($0) + "1"]?.value } == ["Important", "Urgent", "Template", "Date"])
        #expect(cells["A2"]?.value == "No")
        #expect(cells["B2"]?.value == "Yes")
    }

    @Test("Empty values export as empty cells, not placeholders")
    func emptyValues() async throws {
        let env = try TestEnvironment()
        // No calendar sync, no tags, no notes.
        env.settings.calendarSyncEnabled = false
        let template = try env.makeTemplate(tags: [])
        try await record(env, template, start: date(2026, 9, 16, 9), minutes: 30)
        let columns = WorkLogColumnSelection([.tags, .notes, .calendar, .calendarEventIdentifier, .calendarEventStatus, .taskPriority])
        let cells = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, columns: columns, includesSummary: false).data)
            .cells(sheet: 1)
        #expect((cells["A2"]?.value ?? "") == "")
        #expect((cells["B2"]?.value ?? "") == "")
        #expect((cells["C2"]?.value ?? "") == "")
        #expect((cells["D2"]?.value ?? "") == "")
        #expect(cells["E2"]?.value == "Not in Calendar")
        #expect(cells["F2"]?.value == "Not Urgent + Not Important")
    }

    @Test("Deselecting every column is refused instead of writing an empty file")
    func noColumnsSelected() async throws {
        let env = try TestEnvironment()
        try await record(env, try env.makeTemplate(), start: date(2026, 9, 16, 9), minutes: 30)
        var selection = WorkLogColumnSelection.default
        selection.deselectAll()
        #expect(selection.isEmpty)
        #expect(throws: WorkLogExportError.noColumnsSelected) {
            try service(env).workbookData(scope: .all, filter: nil, columns: selection, includesSummary: true)
        }
        let outcome = await service(env).export(scope: .all, filter: nil, columns: selection, includesSummary: true,
                                                destination: NeverChosenDestination())
        #expect(outcome == .failed(.noColumnsSelected))
        #expect(WorkLogExportError.noColumnsSelected.recoverySuggestion != nil)
    }

    @Test("Selections toggle, reorder, and round-trip through settings")
    func selectionEditing() {
        var selection = WorkLogColumnSelection([.date, .template, .activeDuration])
        selection.toggle(.urgent)
        selection.toggle(.important)
        #expect(selection.columns == [.date, .template, .activeDuration, .urgent, .important])
        selection.toggle(.template)
        #expect(selection.contains(.template) == false)
        #expect(selection.count == 4)

        // Move Urgent and Important to the front.
        selection.move(fromOffsets: IndexSet([2, 3]), toOffset: 0)
        #expect(selection.columns == [.urgent, .important, .date, .activeDuration])

        let restored = WorkLogColumnSelection(storageValue: selection.storageValue)
        #expect(restored == selection)
        #expect(WorkLogColumnSelection(storageValue: "") == nil)
        #expect(WorkLogColumnSelection(storageValue: "nonsense") == nil)
        // Unknown names from a newer version are ignored, known ones kept.
        #expect(WorkLogColumnSelection(storageValue: "date,unknown,urgent")?.columns == [.date, .urgent])
        // Duplicates collapse.
        #expect(WorkLogColumnSelection([.date, .date, .urgent]).columns == [.date, .urgent])

        selection.selectAll()
        #expect(selection.columns == WorkLogExportColumn.allCases)
    }

    @Test("Presets describe themselves and are recognised when selected")
    func presets() {
        #expect(WorkLogExportPreset.basic.selection.columns == [.date, .template, .activeDuration])
        #expect(WorkLogExportPreset.priorityAnalysis.selection.contains(.urgent))
        #expect(WorkLogExportPreset.priorityAnalysis.selection.contains(.important))
        #expect(WorkLogExportPreset.everything.selection.count == WorkLogExportColumn.allCases.count)
        #expect(WorkLogExportPreset.matching(WorkLogExportPreset.detailed.selection) == .detailed)
        #expect(WorkLogExportPreset.matching(WorkLogColumnSelection([.notes])) == nil)
        // The shipped default is not a preset; it is the full Work Logs row.
        #expect(WorkLogColumnSelection.default.contains(.urgent))
        #expect(WorkLogColumnSelection.default.contains(.important))
        #expect(WorkLogColumnSelection.default.contains(.taskPriority) == false)
    }

    @Test("The Summary sheet totals work by task priority")
    func summaryPriority() async throws {
        let env = try TestEnvironment()
        let urgent = try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: true))
        let calm = try env.makeTemplate(name: "Reading", icon: "book", tags: [], priority: .default)
        try await record(env, urgent, start: date(2026, 9, 15, 9), minutes: 60)
        try await record(env, calm, start: date(2026, 9, 15, 14), minutes: 20)

        let cells = try XLSXReader(try service(env).workbookData(scope: .all, filter: nil, includesSummary: true).data).cells(sheet: 2)
        let values = cells.mapValues(\.value)
        func row(labeled label: String) -> Int? {
            values.first { $0.key.hasPrefix("A") && $0.value == label }.flatMap { Int($0.key.dropFirst()) }
        }
        let header = try #require(row(labeled: "Work by Task Priority"))
        #expect(values["A\(header + 1)"] == "Urgent + Important")
        #expect(values["B\(header + 1)"] == "1")
        #expect(abs((Double(values["C\(header + 1)"] ?? "") ?? 0) * 1440 - 60) < 1e-6)
        #expect(abs((Double(values["D\(header + 1)"] ?? "") ?? 0) - 0.75) < 1e-9)
        #expect(values["A\(header + 4)"] == "Not Urgent + Not Important")
        #expect(values["A\(header + 5)"] == "Urgent (any)")
        #expect(values["A\(header + 6)"] == "Important (any)")
    }

    @Test("The preview shows readable values for the chosen columns only")
    func preview() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: false))
        for day in 1...8 {
            try await record(env, template, start: date(2026, 9, day, 9), minutes: 90)
        }
        env.clock.now = date(2026, 9, 16, 12)
        let columns = WorkLogColumnSelection([.date, .template, .activeDuration, .urgent, .important])
        let preview = try service(env).preview(scope: .all, filter: nil, columns: columns)
        #expect(preview.headers == ["Date", "Template", "Active Duration", "Urgent", "Important"])
        #expect(preview.total == 8)
        #expect(preview.rows.count == 5)
        #expect(preview.rows.allSatisfy { $0.count == 5 })
        #expect(preview.rows.last?[1] == "Software Engineering")
        #expect(preview.rows.last?[2] == "1h 30m")
        #expect(preview.rows.last?[3] == "Yes")
        #expect(preview.rows.last?[4] == "No")

        // No work: headers only, no rows, no misleading count.
        let fresh = try TestEnvironment()
        let empty = try service(fresh).preview(scope: .all, filter: nil, columns: columns)
        #expect(empty.rows.isEmpty)
        #expect(empty.total == 0)
    }
}

@MainActor
private final class NeverChosenDestination: ExportDestinationProviding {
    func chooseDestination(suggestedName: String) async -> URL? {
        Issue.record("the Save panel must not open when the export can't be built")
        return nil
    }
}
