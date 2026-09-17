import Foundation
import Testing
@testable import CalendarTimeLoggerKit

/// Thirty consecutive days of realistic use, driven through the real services
/// against an isolated on-disk store in the temporary directory.
///
/// Every session is recorded through `SessionService` with a controlled clock
/// (start, pause, resume, finish, cancel, quick tasks, template changes), so
/// timings, Calendar events, analytics, filters, and export are the app's own
/// results. An independent ledger of what each day did is kept alongside, and
/// the app's figures are checked against it. The user's real store, settings,
/// and calendars are never touched: the store is a temporary file, settings use
/// a throwaway defaults suite, and Calendar is the in-memory mock.
///
/// See Documentation/Testing/30-Day Regression.md.
@MainActor
@Suite("30-day regression")
struct ThirtyDayRegressionTests {
    /// What the ledger expects a completed session to be.
    struct Expected {
        let id: UUID
        let templateName: String
        let category: String
        let start: Date
        let end: Date
        let active: TimeInterval
        let priority: TaskPriority
    }

    static let firstDay = TestDates.date(2026, 8, 1)

    static func day(_ number: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = TestDates.calendar
        let day = calendar.date(byAdding: .day, value: number - 1, to: firstDay)!
        return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    /// Runs one session: start at `start`, optional pauses as (after minutes, length minutes),
    /// finish after `minutes` of wall-clock time.
    @discardableResult
    static func work(
        _ env: TestEnvironment,
        _ template: WorkTemplate,
        at start: Date,
        minutes: Double,
        pauses: [(after: Double, length: Double)] = [],
        priority: TaskPriority? = nil,
        category: String? = nil,
        note: String = "",
        ledger: inout [Expected]
    ) async throws -> WorkSession {
        env.clock.now = start
        let session = try env.sessionService.start(template: template, priority: priority, category: category)
        var elapsed = 0.0
        var paused = 0.0
        for pause in pauses {
            env.clock.advance(minutes: pause.after - elapsed)
            try env.sessionService.pause()
            env.clock.advance(minutes: pause.length)
            try env.sessionService.resume()
            elapsed = pause.after + pause.length
            paused += pause.length
        }
        env.clock.advance(minutes: minutes - elapsed)
        if !note.isEmpty { try env.sessionService.appendNote(note) }
        try await env.sessionService.finish()
        ledger.append(Expected(id: session.id, templateName: session.templateName, category: category ?? template.category,
                               start: start, end: start.addingTimeInterval(minutes * 60),
                               active: (minutes - paused) * 60, priority: priority ?? template.taskPriority))
        return session
    }

    static func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ctl-30-day-\(UUID().uuidString).store")
    }

    @Test("Thirty consecutive days of work keep every session, category, priority, total, and export correct")
    func thirtyDays() async throws {
        let url = Self.storeURL()
        defer { StoreMigrationTests.remove(url) }
        var ledger: [Expected] = []
        var cancelledIDs: [UUID] = []
        let calendar = TestDates.calendar

        // MARK: Days 1–28, first launch
        do {
            let env = try TestEnvironment(clock: TestClock(Self.day(1, 8)), persistence: try PersistenceService.open(url: url))
            let menuBar = MenuBarService(persistence: env.persistence, settings: env.settings)
            try env.persistence.seedDefaultTemplatesIfNeeded(defaults: env.defaults)
            let defaults = try env.persistence.templates()
            #expect(defaults.map(\.category) == ["Development", "Education", "Research", "Content", "Design"])
            let study = defaults[1], research = defaults[2], writing = defaults[3], design = defaults[4]

            // Day 1: a new template with a category; Start Work creates no event; Finish Work does.
            let engineering = try env.persistence.createTemplate(WorkTemplateDraft(
                name: "Client Project", icon: "hammer", category: "Development", tags: ["client"],
                taskPriority: TaskPriority(isUrgent: true, isImportant: true)
            ), now: env.clock.now)
            #expect(menuBar.presentation(for: nil, now: env.clock.now).showsIdentity)
            env.clock.now = Self.day(1, 9)
            let first = try env.sessionService.start(template: engineering)
            #expect(first.category == "Development")
            #expect(env.calendarProvider.events.isEmpty)
            env.clock.now = Self.day(1, 10, 30)
            let firstCompletion = try await env.sessionService.finish()
            ledger.append(Expected(id: first.id, templateName: "Client Project", category: "Development",
                                   start: Self.day(1, 9), end: Self.day(1, 10, 30), active: 90 * 60,
                                   priority: TaskPriority(isUrgent: true, isImportant: true)))
            #expect(firstCompletion.calendarOutcome?.succeeded == true)
            let firstEvent = try #require(env.calendarProvider.events[first.calendarEventIdentifier ?? ""])
            #expect(firstEvent.record.startDate == Self.day(1, 9))
            #expect(firstEvent.record.endDate == Self.day(1, 10, 30))
            #expect(firstEvent.notes.contains("Category: Development"))
            #expect(firstEvent.record.url == CalendarOwnership.url(for: first.id))
            try await Self.work(env, study, at: Self.day(1, 14), minutes: 50, ledger: &ledger)

            // Days 2–7: several sessions a day, across categories and all four priority combinations.
            let combos = TaskPriorityQuadrant.displayOrder.map(\.priority)
            for number in 2...7 {
                try await Self.work(env, engineering, at: Self.day(number, 9), minutes: 120 + Double(number * 5),
                                    priority: combos[number % 4], ledger: &ledger)
                try await Self.work(env, number.isMultiple(of: 2) ? research : writing, at: Self.day(number, 13),
                                    minutes: 45, priority: combos[(number + 1) % 4], note: "Day \(number) notes", ledger: &ledger)
                if number == 3 {
                    // A quick task, and a session started by mistake and cancelled.
                    env.clock.now = Self.day(3, 16)
                    let quick = try env.sessionService.startQuickTask(QuickTaskDraft(
                        name: "Hotfix release", taskPriority: TaskPriority(isUrgent: true, isImportant: false),
                        category: "Development", tags: ["release"]))
                    env.clock.advance(minutes: 35)
                    try await env.sessionService.finish()
                    ledger.append(Expected(id: quick.id, templateName: "Hotfix release", category: "Development",
                                           start: Self.day(3, 16), end: Self.day(3, 16, 35), active: 35 * 60,
                                           priority: TaskPriority(isUrgent: true, isImportant: false)))
                    env.clock.now = Self.day(3, 18)
                    let mistake = try env.sessionService.start(template: design)
                    env.clock.advance(minutes: 3)
                    try env.sessionService.cancel()
                    cancelledIDs.append(mistake.id)
                    #expect(mistake.calendarEventIdentifier == nil)
                }
                if number == 6 {
                    try await Self.work(env, design, at: Self.day(6, 16), minutes: 70, category: "Content", ledger: &ledger)
                }
            }

            // Days 8–14: pauses, resumes, long sessions, one past midnight, and the menu bar throughout.
            for number in 8...14 {
                let long = number == 9 || number == 12
                let session = try await {
                    env.clock.now = Self.day(number, 9)
                    let session = try env.sessionService.start(template: engineering)
                    let working = menuBar.presentation(for: env.sessionService.activeSession, now: env.clock.now)
                    #expect(!working.showsIdentity)
                    env.clock.advance(minutes: 50)
                    try env.sessionService.pause()
                    #expect(menuBar.presentation(for: env.sessionService.activeSession, now: env.clock.now)
                        .segments.first?.kind == .pausedIndicator)
                    env.clock.advance(minutes: 10)
                    try env.sessionService.resume()
                    env.clock.advance(minutes: long ? 180 : 40)
                    try env.sessionService.pause()
                    env.clock.advance(minutes: 5)
                    try env.sessionService.resume()
                    env.clock.advance(minutes: 15)
                    try await env.sessionService.finish()
                    #expect(menuBar.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)
                    return session
                }()
                let wall: Double = 50 + 10 + (long ? 180 : 40) + 5 + 15
                ledger.append(Expected(id: session.id, templateName: "Client Project", category: "Development",
                                       start: Self.day(number, 9), end: Self.day(number, 9).addingTimeInterval(wall * 60),
                                       active: (wall - 15) * 60, priority: engineering.taskPriority))
                #expect(session.pauses.count == 2)
                try await Self.work(env, study, at: Self.day(number, 15), minutes: 60, pauses: [(20, 10)], ledger: &ledger)
                if number == 10 {
                    try await Self.work(env, research, at: Self.day(10, 23, 20), minutes: 100, note: "Late experiment", ledger: &ledger)
                }
            }

            // Days 15–21: template and category edits never rewrite history.
            let beforeEdits = Dictionary(uniqueKeysWithValues: try env.persistence.completedSessions().map { ($0.id, $0.category) })
            env.clock.now = Self.day(15, 8)
            var draft = engineering.draft
            draft.category = "Professional Work"
            try env.persistence.updateTemplate(engineering, with: draft, now: env.clock.now)
            for number in 15...21 {
                try await Self.work(env, engineering, at: Self.day(number, 9), minutes: 150, pauses: [(60, 15)], ledger: &ledger)
                if number == 18 {
                    env.clock.now = Self.day(18, 12)
                    #expect(try env.persistence.renameCategory("Education", to: "Learning", now: env.clock.now) == 1)
                    #expect(study.category == "Learning")
                }
                try await Self.work(env, number < 18 ? writing : study, at: Self.day(number, 14), minutes: 40, ledger: &ledger)
                if number == 20 {
                    // Started from the wrong template, then moved: the inherited category follows.
                    env.clock.now = Self.day(20, 17)
                    let moved = try env.sessionService.start(template: writing)
                    env.clock.advance(minutes: 10)
                    try env.sessionService.changeTemplate(to: research)
                    #expect(moved.category == "Research")
                    env.clock.advance(minutes: 30)
                    try await env.sessionService.finish()
                    ledger.append(Expected(id: moved.id, templateName: "Research", category: "Research",
                                           start: Self.day(20, 17), end: Self.day(20, 17, 40), active: 40 * 60,
                                           priority: research.taskPriority))
                }
            }
            for session in try env.persistence.completedSessions() {
                if let recorded = beforeEdits[session.id] {
                    #expect(session.category == recorded, "history changed for \(session.templateName) on \(session.startedAt)")
                }
            }
            #expect(ledger.filter { $0.templateName == "Client Project" && $0.start < Self.day(15, 0) }.allSatisfy { $0.category == "Development" })

            // Days 22–28: ordinary work, then analytics, search, filters, and export on day 28.
            for number in 22...28 {
                try await Self.work(env, engineering, at: Self.day(number, 9), minutes: 110,
                                    priority: combos[number % 4], ledger: &ledger)
                try await Self.work(env, number.isMultiple(of: 3) ? design : research, at: Self.day(number, 14),
                                    minutes: 55, pauses: number == 25 ? [(25, 5)] : [], ledger: &ledger)
            }
            env.clock.now = Self.day(28, 20)
            try verifyAnalyticsAndExport(env, ledger: ledger, cancelledIDs: cancelledIDs, now: env.clock.now, calendar: calendar)

            // Day 29 evening: a session is running when the app goes away.
            env.clock.now = Self.day(29, 19)
            let open = try env.sessionService.start(template: research, priority: TaskPriority(isImportant: true))
            env.clock.advance(minutes: 25)
            env.sessionService.recordHeartbeat()
            ledger.append(Expected(id: open.id, templateName: "Research", category: "Research",
                                   start: Self.day(29, 19), end: Self.day(29, 20), active: 60 * 60,
                                   priority: TaskPriority(isImportant: true)))
            #expect(env.calendarProvider.events.count == ledger.count - 1)
        }

        // MARK: Day 29, relaunch against the same store
        let (sessionCount, categoriesBefore) = try await {
            let env = try TestEnvironment(clock: TestClock(Self.day(29, 19, 40)), persistence: try PersistenceService.open(url: url))
            #expect(try env.persistence.completedSessions().count == ledger.count - 1)
            let recovered = try #require(env.sessionService.pendingRecovery)
            #expect(recovered.id == ledger.last?.id)
            #expect(recovered.category == "Research")
            #expect(try env.persistence.templates().map(\.category)
                    == ["Development", "Learning", "Research", "Content", "Design", "Professional Work"])
            try await env.sessionService.resolveRecovery(.resume)
            env.clock.now = Self.day(29, 20)
            try await env.sessionService.finish()
            // Every recorded session reopened with its own category and priority.
            let stored = try env.persistence.completedSessions()
            for expected in ledger {
                let session = try #require(stored.first { $0.id == expected.id })
                #expect(session.category == expected.category)
                #expect(session.taskPriority == expected.priority)
                #expect(session.startedAt == expected.start)
                #expect(session.endedAt == expected.end)
                #expect(abs(WorkLog(session: session).activeDuration - expected.active) < 0.001)
            }
            for id in cancelledIDs {
                #expect(env.persistence.session(id: id)?.state == .cancelled)
            }
            return (stored.count, Set(stored.map(\.category)))
        }()
        #expect(sessionCount == ledger.count)
        #expect(categoriesBefore == ["Development", "Education", "Research", "Content", "Design", "Professional Work", "Learning"])

        // MARK: Day 30, the full workflow after another relaunch
        let env = try TestEnvironment(clock: TestClock(Self.day(30, 8)), persistence: try PersistenceService.open(url: url))
        #expect(env.sessionService.pendingRecovery == nil)
        let menuBar = MenuBarService(persistence: env.persistence, settings: env.settings)
        let templates = try env.persistence.templates()
        let engineering = try #require(templates.first { $0.name == "Client Project" })
        let writing = try #require(templates.first { $0.name == "Writing" })

        let today = try env.persistence.createTemplate(WorkTemplateDraft(
            name: "Release Notes", icon: "doc.text", category: "content", taskPriority: TaskPriority(isImportant: true)
        ), now: env.clock.now)
        #expect(today.category == "Content")

        env.clock.now = Self.day(30, 9)
        let session = try env.sessionService.start(template: engineering, priority: TaskPriority(isUrgent: true, isImportant: false),
                                                   category: "Operations")
        #expect(menuBar.presentation(for: env.sessionService.activeSession, now: env.clock.now).plainText.contains("Client Project"))
        env.clock.advance(minutes: 30)
        try env.sessionService.pause()
        env.clock.advance(minutes: 10)
        try env.sessionService.resume()
        try env.sessionService.updateTaskPriority(TaskPriority(isUrgent: true, isImportant: true))
        try env.sessionService.changeTemplate(to: writing)
        #expect(session.category == "Operations") // chosen for the session, so it stays
        try env.sessionService.appendNote("Wrapped up the month")
        env.clock.advance(minutes: 50)
        let completion = try await env.sessionService.finish()
        #expect(completion.log.category == "Operations")
        #expect(completion.log.templateName == "Writing")
        #expect(completion.log.activeDuration == 80 * 60)
        #expect(completion.calendarOutcome?.succeeded == true)
        #expect(menuBar.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)
        ledger.append(Expected(id: session.id, templateName: "Writing", category: "Operations",
                               start: Self.day(30, 9), end: Self.day(30, 10, 30), active: 80 * 60,
                               priority: TaskPriority(isUrgent: true, isImportant: true)))
        try await Self.work(env, today, at: Self.day(30, 14), minutes: 45, ledger: &ledger)

        env.clock.now = Self.day(30, 21)
        try verifyAnalyticsAndExport(env, ledger: ledger, cancelledIDs: cancelledIDs, now: env.clock.now, calendar: calendar)
        #expect(Set(ledger.map { calendar.startOfDay(for: $0.start) }).count == 30)
        // The dataset documented in 30-Day Regression.md: 63 completed sessions and 1 cancelled.
        #expect(ledger.count == 63)
        #expect(cancelledIDs.count == 1)
        #expect(ledger.map { $0.end.timeIntervalSince($0.start) }.max() == 260.0 * 60)
        #expect(ledger.map { $0.end.timeIntervalSince($0.start) }.min() == 35.0 * 60)
    }

    /// Checks analytics, search, filters, and export against the ledger.
    func verifyAnalyticsAndExport(_ env: TestEnvironment, ledger: [Expected], cancelledIDs: [UUID], now: Date, calendar: Calendar) throws {
        let logs = try env.persistence.completedSessions().map { WorkLog(session: $0) }
        #expect(logs.count == ledger.count)
        #expect(!logs.contains { cancelledIDs.contains($0.id) })

        // Category totals for Today, Last 7 Days, and Last 30 Days, each against the ledger.
        let endOfToday = calendar.dateInterval(of: .day, for: now)!.end
        let ranges: [DateInterval] = [
            calendar.dateInterval(of: .day, for: now)!,
            DateInterval(start: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!, end: endOfToday),
            DateInterval(start: calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!, end: endOfToday)
        ]
        for range in ranges {
            let inRange = ledger.filter { $0.start >= range.start && $0.start < range.end }
            let totals = WorkAnalytics.categoryTotals(WorkAnalytics.logs(logs, in: range))
            let expected = Dictionary(grouping: inRange) { WorkCategory.key($0.category) }
            #expect(totals.count == expected.count)
            let all = inRange.reduce(0) { $0 + $1.active }
            for total in totals {
                let group = try #require(expected[total.key])
                let active = group.reduce(0) { $0 + $1.active }
                #expect(abs(total.duration - active) < 0.001, "\(total.name) duration")
                #expect(total.sessionCount == group.count)
                #expect(abs(total.share - active / all) < 1e-9)
                #expect(abs(total.templates.reduce(0) { $0 + $1.duration } - active) < 0.001)
                #expect(abs(total.quadrants.reduce(0) { $0 + $1.duration } - active) < 0.001)
                for quadrant in total.quadrants {
                    let matching = group.filter { $0.priority.quadrant == quadrant.quadrant }
                    #expect(quadrant.sessionCount == matching.count)
                }
            }
            if totals.count > 0 { #expect(abs(totals.reduce(0) { $0 + $1.share } - 1) < 1e-9) }
        }

        // Search and filters.
        let development = WorkLogQuery.filter(logs, with: WorkLogFilter(category: "development"))
        #expect(development.count == ledger.filter { WorkCategory.matches($0.category, "Development") }.count)
        let urgentResearch = WorkLogQuery.filter(logs, with: WorkLogFilter(priority: .urgent, category: "Research"))
        #expect(urgentResearch.count == ledger.filter { $0.category == "Research" && $0.priority.isUrgent }.count)
        #expect(WorkLogQuery.filter(logs, with: WorkLogFilter(searchText: "Professional")).count
                == ledger.filter { $0.category == "Professional Work" }.count)
        #expect(WorkLogQuery.filter(logs, with: WorkLogFilter(searchText: "Late experiment")).count == 1)

        // Export exactly the chosen columns, and read the workbook back.
        let service = WorkLogExportService(persistence: env.persistence, calendarName: { _ in nil }, calendar: calendar, now: { now })
        let columns = WorkLogColumnSelection([.date, .template, .category, .duration, .urgent, .important])
        let clock = ContinuousClock()
        var built: (data: Data, count: Int)?
        let elapsed = try clock.measure {
            built = try service.workbookData(scope: .all, filter: nil, columns: columns, includesSummary: true)
        }
        #expect(elapsed < .seconds(5))
        let output = try #require(built)
        #expect(output.count == ledger.count)
        let reader = try XLSXReader(output.data)
        #expect(reader.allPartsAreWellFormed())
        let cells = try reader.cells(sheet: 1)
        #expect((0..<6).map { cells[XLSXWriter.columnName($0) + "1"]?.value }
                == ["Date", "Template", "Category", "Duration", "Urgent", "Important"])
        #expect(cells["G1"] == nil)
        // Rows are oldest first, like the ledger once sorted.
        for (index, expected) in ledger.sorted(by: { $0.start < $1.start }).enumerated() {
            let row = index + 2
            #expect(cells["B\(row)"]?.value == expected.templateName)
            #expect(cells["C\(row)"]?.value == expected.category)
            let wall = expected.end.timeIntervalSince(expected.start) / 86_400
            #expect(abs((Double(cells["D\(row)"]?.value ?? "") ?? -1) - wall) < 1e-9)
            #expect(cells["E\(row)"]?.value == TaskPriority.yesNo(expected.priority.isUrgent))
            #expect(cells["F\(row)"]?.value == TaskPriority.yesNo(expected.priority.isImportant))
        }
        #expect(cells["A\(ledger.count + 2)"] == nil)
    }

    @Test("Category analytics stay fast for years of work")
    func analyticsPerformance() {
        let start = TestDates.date(2024, 1, 1, 9)
        let categories = WorkCategory.builtIn + ["Operations", "Client Work"]
        let logs = (0..<20_000).map { index in
            let begin = start.addingTimeInterval(Double(index) * 3 * 3600)
            return WorkLog(templateID: nil, templateName: "Template \(index % 12)", templateIcon: "laptopcomputer",
                           templateColor: TemplatePalette.colors[0].color,
                           timing: SessionTiming(startedAt: begin, endedAt: begin.addingTimeInterval(3600), pauses: []),
                           now: begin.addingTimeInterval(3600),
                           taskPriority: TaskPriorityQuadrant.displayOrder[index % 4].priority,
                           category: categories[index % categories.count])
        }
        let clock = ContinuousClock()
        var totals: [CategoryTotal] = []
        let elapsed = clock.measure { totals = WorkAnalytics.categoryTotals(logs) }
        #expect(totals.count == categories.count)
        #expect(totals.reduce(0) { $0 + $1.sessionCount } == 20_000)
        #expect(elapsed < .seconds(2))
    }
}
