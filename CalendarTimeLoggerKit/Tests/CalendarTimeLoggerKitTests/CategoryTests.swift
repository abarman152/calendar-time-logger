import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Categories")
struct CategoryTests {
    // MARK: Names

    @Test("Names are tidied, compared without case, and never stored blank")
    func names() throws {
        #expect(WorkCategory.normalized("  Deep   Work \n") == "Deep Work")
        #expect(WorkCategory.normalized("   ") == "")
        #expect(WorkCategory.stored("  ") == WorkCategory.defaultName)
        #expect(WorkCategory.matches("research", "Research "))
        #expect(WorkCategory.canonical("research", among: ["Development", "Research"]) == "Research")
        #expect(WorkCategory.canonical("Client Work", among: ["Development"]) == "Client Work")
        #expect(throws: CategoryValidationError.empty) { try WorkCategory.validate(" ") }
        #expect(throws: CategoryValidationError.tooLong(max: WorkCategory.maximumLength)) {
            try WorkCategory.validate(String(repeating: "x", count: WorkCategory.maximumLength + 1))
        }
    }

    @Test("The picker offers the built-ins first, then categories in use, once each")
    func available() {
        let list = WorkCategory.available(inUse: ["Zeta", "research", "Client Work", "client work", ""])
        #expect(list == ["Development", "Education", "Research", "Content", "Design", "General", "Client Work", "Zeta"])
    }

    // MARK: Templates

    @Test("Every default template has a category")
    func defaultTemplates() throws {
        let env = try TestEnvironment()
        try env.persistence.seedDefaultTemplatesIfNeeded(defaults: env.defaults)
        let categories = try env.persistence.templates().map(\.category)
        #expect(categories == ["Development", "Education", "Research", "Content", "Design"])
    }

    @Test("A template can't be saved without a category")
    func categoryRequired() throws {
        let env = try TestEnvironment()
        var draft = WorkTemplateDraft(name: "Reading", icon: "book", category: "   ")
        #expect(throws: TemplateValidationError.invalidCategory(.empty)) { try env.persistence.createTemplate(draft) }
        #expect(try env.persistence.templates().isEmpty)

        draft.category = "Education"
        let template = try env.persistence.createTemplate(draft)
        var edit = template.draft
        edit.category = ""
        #expect(throws: TemplateValidationError.invalidCategory(.empty)) { try env.persistence.updateTemplate(template, with: edit) }
        #expect(template.category == "Education")
        #expect(TemplateValidationError.invalidCategory(.empty).recoverySuggestion != nil)
    }

    @Test("A typed category joins an existing one that differs only by case")
    func canonicalSpelling() throws {
        let env = try TestEnvironment()
        try env.makeTemplate(name: "Coding", category: "Development")
        let other = try env.makeTemplate(name: "Reviews", category: "  development ")
        #expect(other.category == "Development")
        #expect(try env.persistence.availableCategories().filter { $0 == "Development" }.count == 1)
        // A built-in spelling wins even before any template uses it.
        let reading = try env.makeTemplate(name: "Reading", icon: "book", category: "EDUCATION")
        #expect(reading.category == "Education")
    }

    @Test("Renaming a category changes templates only, never recorded work")
    func renameKeepsHistory() async throws {
        let env = try TestEnvironment()
        let coding = try env.makeTemplate(name: "Coding", category: "Development")
        let reviews = try env.makeTemplate(name: "Reviews", icon: "flask", category: "development")
        let study = try env.makeTemplate(name: "Study", icon: "book", category: "Education")
        try env.sessionService.start(template: coding)
        env.clock.advance(minutes: 40)
        let recorded = try await env.sessionService.finish()

        let changed = try env.persistence.renameCategory("DEVELOPMENT", to: "Professional Work")
        #expect(changed == 2)
        #expect(coding.category == "Professional Work")
        #expect(reviews.category == "Professional Work")
        #expect(study.category == "Education")
        let session = try #require(env.persistence.session(id: recorded.log.id))
        #expect(session.category == "Development")
        #expect(WorkLog(session: session).category == "Development")

        // Renaming onto an existing category merges, using its spelling.
        #expect(try env.persistence.renameCategory("Professional Work", to: "education") == 2)
        #expect(Set(try env.persistence.templates().map(\.category)) == ["Education"])
        #expect(throws: TemplateValidationError.invalidCategory(.empty)) { try env.persistence.renameCategory("Education", to: " ") }
    }

    // MARK: Sessions

    @Test("A session starts with its template's category, or one chosen for it")
    func sessionCategory() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(category: "Development")
        let session = try env.sessionService.start(template: template)
        #expect(session.category == "Development")
        env.clock.advance(minutes: 20)
        try await env.sessionService.finish()

        let override = try env.sessionService.start(template: template, category: "Research")
        #expect(override.category == "Research")
        #expect(template.category == "Development")
    }

    @Test("Changing a template's category never changes sessions recorded before")
    func historyIsPreserved() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(category: "Development")
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 45)
        let first = try await env.sessionService.finish()

        var draft = template.draft
        draft.category = "Professional Work"
        try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)

        env.clock.advance(minutes: 60)
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 30)
        let second = try await env.sessionService.finish()

        let logs = try env.persistence.completedSessions().map { WorkLog(session: $0) }
        #expect(logs.first { $0.id == first.log.id }?.category == "Development")
        #expect(logs.first { $0.id == second.log.id }?.category == "Professional Work")
    }

    @Test("The open session's category can change without touching the template")
    func liveChange() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(category: "Development")
        let session = try env.sessionService.start(template: template)
        env.clock.advance(minutes: 10)
        try env.sessionService.updateCategory("  Research ")
        #expect(session.category == "Research")
        #expect(session.modifiedAt == env.clock.now)
        try env.sessionService.updateCategory("")
        #expect(session.category == WorkCategory.defaultName)
        try env.sessionService.updateCategory("research")
        #expect(session.category == "Research")
        env.clock.advance(minutes: 10)
        let completion = try await env.sessionService.finish()
        #expect(completion.log.category == "Research")
        #expect(template.category == "Development")
    }

    @Test("A quick task keeps the category chosen for it; a blank one is General")
    func quickTask() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.startQuickTask(QuickTaskDraft(name: "Fix the build", category: "Development"))
        #expect(session.category == "Development")
        env.clock.advance(minutes: 5)
        try await env.sessionService.finish()

        let blank = try env.sessionService.startQuickTask(QuickTaskDraft(name: "Inbox", category: " "))
        #expect(blank.category == WorkCategory.defaultName)
    }

    @Test("Editing a completed session can correct its category")
    func editCompleted() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: try env.makeTemplate(category: "Development"))
        env.clock.advance(minutes: 30)
        let completion = try await env.sessionService.finish()
        let session = try #require(env.persistence.session(id: completion.log.id))
        var edit = SessionEdit(session: session)
        #expect(edit.category == "Development")
        edit.category = "Research"
        _ = try await env.sessionService.edit(session, with: edit)
        #expect(session.category == "Research")
    }

    @Test("Moving a session to another template moves an inherited category, and keeps a chosen one")
    func changeTemplate() async throws {
        let env = try TestEnvironment()
        let coding = try env.makeTemplate(name: "Coding", category: "Development")
        let study = try env.makeTemplate(name: "Study", icon: "book", category: "Education")

        let inherited = try env.sessionService.start(template: coding)
        try env.sessionService.changeTemplate(to: study)
        #expect(inherited.category == "Education")
        env.clock.advance(minutes: 15)
        try await env.sessionService.finish()

        let chosen = try env.sessionService.start(template: coding, category: "Research")
        try env.sessionService.changeTemplate(to: study)
        #expect(chosen.category == "Research")
        env.clock.advance(minutes: 15)
        let completion = try await env.sessionService.finish()

        // The same rule applies when a completed Work Log is moved.
        let session = try #require(env.persistence.session(id: completion.log.id))
        _ = try await env.sessionService.reassignTemplate(of: session, to: coding)
        #expect(session.category == "Research")
        let other = try #require(try env.persistence.completedSessions().first { $0.id != session.id })
        _ = try await env.sessionService.reassignTemplate(of: other, to: coding)
        #expect(other.category == "Development")
    }

    @Test("Calendar event notes name the category")
    func calendarNotes() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: try env.makeTemplate(category: "Development", calendarIdentifier: "work"))
        env.clock.advance(minutes: 30)
        let completion = try await env.sessionService.finish()
        let identifier = try #require(env.persistence.session(id: completion.log.id)?.calendarEventIdentifier)
        #expect(env.calendarProvider.events[identifier]?.notes.contains("Category: Development") == true)
    }

    // MARK: Work Logs

    @Test("Work Logs filter by category without case, and search matches it")
    func filtering() {
        let logs = [
            log("Coding", category: "Development", start: TestDates.date(2026, 9, 15, 9), minutes: 60),
            log("Reviews", category: "development", start: TestDates.date(2026, 9, 15, 11), minutes: 30),
            log("Study", category: "Education", start: TestDates.date(2026, 9, 15, 14), minutes: 45)
        ]
        let byCategory = WorkLogQuery.filter(logs, with: WorkLogFilter(category: "DEVELOPMENT"))
        #expect(byCategory.map(\.templateName) == ["Coding", "Reviews"])
        #expect(WorkLogFilter(category: "Education").isActive)
        #expect(WorkLogQuery.filter(logs, with: WorkLogFilter(searchText: "educ")).map(\.templateName) == ["Study"])
        #expect(WorkLogQuery.allCategories(in: logs) == ["development", "Education"])
    }

    // MARK: Analytics

    @Test("No sessions means no categories")
    func analyticsEmpty() {
        #expect(WorkAnalytics.categoryTotals([]).isEmpty)
    }

    @Test("One session is the whole of its category")
    func analyticsOne() throws {
        let totals = WorkAnalytics.categoryTotals([log("Coding", category: "Development", start: TestDates.date(2026, 9, 15, 9), minutes: 50)])
        let only = try #require(totals.first)
        #expect(totals.count == 1)
        #expect(only.name == "Development")
        #expect(only.duration == 50 * 60)
        #expect(only.sessionCount == 1)
        #expect(only.share == 1)
    }

    @Test("Totals, session counts, and shares per category, longest first")
    func analyticsTotals() throws {
        let day = TestDates.date(2026, 9, 15)
        let logs = [
            log("Coding", category: "Development", start: day.addingTimeInterval(9 * 3600), minutes: 120, priority: .init(isUrgent: true, isImportant: true)),
            log("Reviews", category: "development", start: day.addingTimeInterval(12 * 3600), minutes: 60, priority: .init(isImportant: true)),
            log("Coding", category: "Development", start: day.addingTimeInterval(13 * 3600), minutes: 60, pauseMinutes: 20),
            log("Research", category: "Research", start: day.addingTimeInterval(15 * 3600), minutes: 80),
            log("Study", category: "Education", start: day.addingTimeInterval(17 * 3600), minutes: 40, priority: .init(isUrgent: true))
        ]
        let totals = WorkAnalytics.categoryTotals(logs)
        #expect(totals.map(\.name) == ["Development", "Research", "Education"])
        let development = totals[0]
        // 120 + 60 + (60 - 20 paused) active minutes.
        #expect(development.duration == 220 * 60)
        #expect(development.sessionCount == 3)
        #expect(abs(development.share - 220.0 / 340.0) < 1e-9)
        #expect(abs(totals.reduce(0) { $0 + $1.share } - 1) < 1e-9)
        #expect(totals[1].duration == 80 * 60)
        #expect(totals[2].sessionCount == 1)

        // Templates inside a category.
        #expect(development.templates.map(\.name) == ["Coding", "Reviews"])
        #expect(development.templates.map(\.duration) == [160 * 60, 60 * 60])

        // All four priority combinations inside a category, always present.
        #expect(development.quadrants.map(\.quadrant) == TaskPriorityQuadrant.displayOrder)
        let quadrants = Dictionary(uniqueKeysWithValues: development.quadrants.map { ($0.quadrant, $0) })
        #expect(quadrants[.urgentImportant]?.duration == 120.0 * 60)
        #expect(quadrants[.notUrgentImportant]?.duration == 60.0 * 60)
        #expect(quadrants[.neither]?.duration == 40.0 * 60)
        #expect(quadrants[.urgentNotImportant]?.sessionCount == 0)
        #expect(totals[2].quadrants.first { $0.quadrant == .urgentNotImportant }?.share == 1)
    }

    @Test("Category totals use only the selected date range")
    func analyticsDateRange() {
        let logs = [
            log("Coding", category: "Development", start: TestDates.date(2026, 9, 1, 9), minutes: 300),
            log("Study", category: "Education", start: TestDates.date(2026, 9, 14, 9), minutes: 60),
            log("Coding", category: "Development", start: TestDates.date(2026, 9, 15, 9), minutes: 30)
        ]
        let today = WorkAnalytics.dayInterval(containing: TestDates.date(2026, 9, 15, 12), calendar: TestDates.calendar)
        let totals = WorkAnalytics.categoryTotals(WorkAnalytics.logs(logs, in: today))
        #expect(totals.map(\.name) == ["Development"])
        #expect(totals.first?.duration == 30.0 * 60)
        #expect(totals.first?.share == 1)
    }

    @Test("A session that crosses midnight counts toward the day it started")
    func analyticsMidnight() {
        let late = log("Coding", category: "Development", start: TestDates.date(2026, 9, 14, 23, 30), minutes: 90)
        let calendar = TestDates.calendar
        let fourteenth = WorkAnalytics.dayInterval(containing: TestDates.date(2026, 9, 14, 12), calendar: calendar)
        let fifteenth = WorkAnalytics.dayInterval(containing: TestDates.date(2026, 9, 15, 12), calendar: calendar)
        #expect(WorkAnalytics.categoryTotals(WorkAnalytics.logs([late], in: fourteenth)).first?.duration == 90.0 * 60)
        #expect(WorkAnalytics.categoryTotals(WorkAnalytics.logs([late], in: fifteenth)).isEmpty)
    }

    @Test("A renamed category reports old and new names separately; the newest spelling names a group")
    func analyticsRenamed() {
        let logs = [
            log("Coding", category: "Development", start: TestDates.date(2026, 9, 1, 9), minutes: 60),
            log("Coding", category: "Professional Work", start: TestDates.date(2026, 9, 2, 9), minutes: 60),
            log("Coding", category: "professional work", start: TestDates.date(2026, 9, 3, 9), minutes: 30)
        ]
        let totals = WorkAnalytics.categoryTotals(logs)
        #expect(totals.map(\.name) == ["professional work", "Development"])
        #expect(totals.first?.sessionCount == 2)
    }

    // MARK: Export

    @Test("Category is a selectable export column, written in the chosen order from recorded data")
    func exportColumn() async throws {
        let env = try TestEnvironment()
        let coding = try env.makeTemplate(name: "Software Engineering", category: "Development",
                                          priority: TaskPriority(isUrgent: true, isImportant: true))
        let study = try env.makeTemplate(name: "Study", icon: "book", category: "Education", priority: .default)
        env.clock.now = TestDates.date(2026, 9, 14, 9)
        try env.sessionService.start(template: coding)
        env.clock.advance(minutes: 90)
        try await env.sessionService.finish()
        env.clock.now = TestDates.date(2026, 9, 15, 14)
        try env.sessionService.start(template: study, priority: TaskPriority(isImportant: true))
        env.clock.advance(minutes: 45)
        try await env.sessionService.finish()

        let service = WorkLogExportService(persistence: env.persistence, calendarName: { _ in nil },
                                           calendar: TestDates.calendar, now: { env.clock.now })
        let columns = WorkLogColumnSelection([.date, .template, .category, .duration, .urgent, .important])
        let data = try service.workbookData(scope: .all, filter: nil, columns: columns, includesSummary: true).data
        let reader = try XLSXReader(data)
        let cells = try reader.cells(sheet: 1)

        #expect((0..<6).map { cells[XLSXWriter.columnName($0) + "1"]?.value } == ["Date", "Template", "Category", "Duration", "Urgent", "Important"])
        #expect(cells["G1"] == nil)
        #expect(!(try reader.xml("xl/worksheets/sheet1.xml")).contains("Start Time"))
        #expect(cells["B2"]?.value == "Software Engineering")
        #expect(cells["C2"]?.value == "Development")
        #expect(abs(Double(cells["D2"]!.value)! - 90.0 / 1440) < 1e-9)
        #expect(cells["E2"]?.value == "Yes")
        #expect(cells["F2"]?.value == "Yes")
        #expect(cells["B3"]?.value == "Study")
        #expect(cells["C3"]?.value == "Education")
        #expect(abs(Double(cells["D3"]!.value)! - 45.0 / 1440) < 1e-9)
        #expect(cells["E3"]?.value == "No")
        #expect(cells["F3"]?.value == "Yes")

        // The Summary sheet totals work by category.
        let summary = try reader.cells(sheet: 2)
        let header = try #require(summary.first { $0.value.value == "Work by Category" }?.key)
        let row = Int(header.drop { $0.isLetter })!
        #expect(summary["A\(row + 1)"]?.value == "Development")
        #expect(summary["B\(row + 1)"]?.value == "1")
        #expect(summary["A\(row + 2)"]?.value == "Education")

        #expect(WorkLogExportPreset.categoryAnalysis.selection == columns)
        #expect(WorkLogColumnSelection.default.contains(.category))
        #expect(WorkLogExportColumn.category.previewText(for: WorkLogExportRecord(
            log: WorkLog(session: try #require(try env.persistence.completedSessions().first)), calendarName: "", calendarEventIdentifier: ""
        ), calendar: TestDates.calendar) == "Education")
    }

    // MARK: Helpers

    private func log(_ template: String, category: String, start: Date, minutes: Double, pauseMinutes: Double = 0,
                     priority: TaskPriority = .default) -> WorkLog {
        let end = start.addingTimeInterval(minutes * 60)
        let pauses = pauseMinutes > 0
            ? [PauseInterval(start: start.addingTimeInterval(60), end: start.addingTimeInterval(60 + pauseMinutes * 60))]
            : []
        return WorkLog(templateID: nil, templateName: template, templateIcon: "laptopcomputer",
                       templateColor: TemplatePalette.colors[0].color,
                       timing: SessionTiming(startedAt: start, endedAt: end, pauses: pauses), now: end,
                       taskPriority: priority, category: category)
    }
}
