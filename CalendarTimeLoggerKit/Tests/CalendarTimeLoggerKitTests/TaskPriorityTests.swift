import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Task priority")
struct TaskPriorityTests {
    // MARK: Templates

    @Test("A new template defaults to Not Urgent, Not Important")
    func templateDefaults() throws {
        let env = try TestEnvironment()
        let template = try env.persistence.createTemplate(WorkTemplateDraft(name: "Research", icon: "flask"), now: env.clock.now)
        #expect(template.isUrgent == false)
        #expect(template.isImportant == false)
        #expect(template.taskPriority == .default)
        #expect(template.draft.taskPriority == TaskPriority(isUrgent: false, isImportant: false))
        #expect(template.taskPriority.quadrant == .neither)
    }

    @Test("A template created before 1.2 reads as No/No and keeps every other value")
    func legacyTemplateMigration() throws {
        let env = try TestEnvironment()
        // A row written by 1.1: the new attributes take their storage defaults.
        let legacy = WorkTemplate(name: "Study", icon: "book", color: TemplatePalette.colors[2].color,
                                  calendarIdentifier: "work", tags: ["learning"], notes: "Evening reading",
                                  notificationBehavior: NotificationBehavior(notifyOnStart: true, reminderIntervalMinutes: 60),
                                  menuBarConfiguration: MenuBarConfiguration(displayMode: .iconOnly,
                                                                            backgroundColor: HexColor(hex: "#FF453A")),
                                  createdAt: env.clock.now)
        env.persistence.context.insert(legacy)
        try env.persistence.save()

        let loaded = try #require(try env.persistence.templates().first { $0.name == "Study" })
        #expect(loaded.taskPriority == .default)
        // Nothing else was reset.
        #expect(loaded.icon == "book")
        #expect(loaded.color == TemplatePalette.colors[2].color)
        #expect(loaded.calendarIdentifier == "work")
        #expect(loaded.tags == ["learning"])
        #expect(loaded.notes == "Evening reading")
        #expect(loaded.notificationBehavior.reminderIntervalMinutes == 60)
        #expect(loaded.menuBarConfiguration.displayMode == .iconOnly)
        #expect(loaded.menuBarConfiguration.backgroundColor?.hex == "#FF453A")
    }

    @Test("Editing a template stores both flags and keeps the rest of the draft")
    func editTemplatePriority() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        var draft = template.draft
        draft.taskPriority = TaskPriority(isUrgent: true, isImportant: true)
        try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)
        #expect(template.isUrgent)
        #expect(template.isImportant)
        #expect(template.taskPriority.quadrant == .urgentImportant)
        #expect(template.tags == ["coding", "development"])
        #expect(template.draft.taskPriority == draft.taskPriority)

        // Duplicating carries the priority across.
        let copy = try env.persistence.duplicateTemplate(template, now: env.clock.now)
        #expect(copy.taskPriority == template.taskPriority)
    }

    // MARK: Starting a session

    @Test("A session inherits the template's priority")
    func sessionInheritsTemplate() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(priority: TaskPriority(isUrgent: false, isImportant: true))
        let session = try env.sessionService.start(template: template)
        #expect(session.isUrgent == false)
        #expect(session.isImportant)
        #expect(WorkLog(session: session, now: env.clock.now).taskPriority == template.taskPriority)
    }

    @Test("A session-level override is what the work log records")
    func sessionOverride() async throws {
        let env = try TestEnvironment()
        // Template says Not Urgent + Important; the user starts it as Urgent + Not Important.
        let template = try env.makeTemplate(priority: TaskPriority(isUrgent: false, isImportant: true))
        try env.sessionService.start(template: template, priority: TaskPriority(isUrgent: true, isImportant: false))
        env.clock.advance(minutes: 30)
        let completion = try await env.sessionService.finish()
        #expect(completion.log.isUrgent)
        #expect(completion.log.isImportant == false)
        // The template is untouched.
        #expect(template.taskPriority == TaskPriority(isUrgent: false, isImportant: true))
    }

    @Test("Changing the template later never changes recorded work")
    func templateChangeDoesNotRewriteHistory() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: true))
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 45)
        let completion = try await env.sessionService.finish()

        var draft = template.draft
        draft.taskPriority = TaskPriority(isUrgent: false, isImportant: false)
        try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)

        let stored = try #require(env.persistence.session(id: completion.log.id))
        #expect(stored.taskPriority == TaskPriority(isUrgent: true, isImportant: true))
        #expect(WorkLog(session: stored).taskPriority.quadrant == .urgentImportant)
    }

    @Test("Moving a session to another template keeps the session's own priority")
    func reassignKeepsPriority() async throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: true))
        let study = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"],
                                         priority: TaskPriority(isUrgent: false, isImportant: false))
        try env.sessionService.start(template: engineering)
        env.clock.advance(minutes: 20)
        let completion = try await env.sessionService.finish()
        let session = try #require(env.persistence.session(id: completion.log.id))

        _ = try await env.sessionService.reassignTemplate(of: session, to: study)
        #expect(session.templateName == "Study")
        #expect(session.taskPriority == TaskPriority(isUrgent: true, isImportant: true))
    }

    @Test("Priority survives a relaunch against the same store")
    func persistsAcrossRelaunch() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(priority: TaskPriority(isUrgent: true, isImportant: false))
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 15)
        let completion = try await env.sessionService.finish()

        env.relaunch()
        let reloaded = try #require(try env.persistence.completedSessions().first { $0.id == completion.log.id })
        #expect(reloaded.isUrgent)
        #expect(reloaded.isImportant == false)
        #expect(try env.persistence.templates().first?.taskPriority == TaskPriority(isUrgent: true, isImportant: false))
    }

    // MARK: Live changes

    @Test("Priority can be changed while a session runs, and the final value is logged")
    func liveChange() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        let session = try env.sessionService.start(template: template)
        #expect(session.taskPriority == .default)

        env.clock.advance(minutes: 10)
        try env.sessionService.updateTaskPriority(TaskPriority(isUrgent: true, isImportant: true))
        #expect(session.taskPriority.quadrant == .urgentImportant)
        #expect(session.modifiedAt == env.clock.now)

        try env.sessionService.pause()
        env.clock.advance(minutes: 5)
        try env.sessionService.resume()
        env.clock.advance(minutes: 5)
        try env.sessionService.updateTaskPriority(TaskPriority(isUrgent: false, isImportant: true))
        let completion = try await env.sessionService.finish()
        #expect(completion.log.isUrgent == false)
        #expect(completion.log.isImportant)
    }

    @Test("Editing a completed session can correct its priority")
    func editCompletedSession() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: try env.makeTemplate())
        env.clock.advance(minutes: 30)
        let completion = try await env.sessionService.finish()
        let session = try #require(env.persistence.session(id: completion.log.id))

        var edit = SessionEdit(session: session)
        edit.taskPriority = TaskPriority(isUrgent: true, isImportant: true)
        _ = try await env.sessionService.edit(session, with: edit)
        #expect(session.taskPriority.quadrant == .urgentImportant)
    }

    // MARK: Quick tasks

    @Test("A quick task starts a session with its own name and priority, and no template")
    func quickTask() async throws {
        let env = try TestEnvironment()
        let draft = QuickTaskDraft(name: "  Fix the build  ", taskPriority: TaskPriority(isUrgent: true, isImportant: false),
                                   tags: ["#Build", "ci"], notes: "Broke after the merge")
        let session = try env.sessionService.startQuickTask(draft)
        #expect(session.templateID == nil)
        #expect(session.templateName == "Fix the build")
        #expect(session.templateSymbolName == QuickTaskDraft.symbolName)
        #expect(session.tags == ["build", "ci"])
        #expect(session.notes == "Broke after the merge")
        #expect(session.isUrgent)
        #expect(session.isImportant == false)

        env.clock.advance(minutes: 25)
        let completion = try await env.sessionService.finish()
        #expect(completion.log.templateName == "Fix the build")
        #expect(completion.log.taskPriority.quadrant == .urgentNotImportant)
        #expect(try env.persistence.templates().isEmpty)
    }

    @Test("A quick task without a name can't be started")
    func quickTaskValidation() throws {
        let env = try TestEnvironment()
        #expect(QuickTaskDraft(name: "   ").isValid == false)
        #expect(QuickTaskDraft(name: "Review").isValid)
        #expect(throws: SessionError.invalidTaskName) { try env.sessionService.startQuickTask(QuickTaskDraft(name: " ")) }
        #expect(env.sessionService.activeSession == nil)
        // Priority always has a value, so it can never block a start.
        #expect(QuickTaskDraft(name: "Review").taskPriority == .default)
    }

    @Test("Only one session can be open, whether it is a template session or a quick task")
    func oneOpenSession() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        try env.sessionService.start(template: template)
        #expect(throws: SessionError.sessionAlreadyActive(templateName: "Software Engineering")) {
            try env.sessionService.startQuickTask(QuickTaskDraft(name: "Fix the build"))
        }
    }

    // MARK: Filtering

    @Test("Work Logs can be filtered by priority")
    func filtering() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        func log(_ urgent: Bool, _ important: Bool) -> WorkLog {
            WorkLog(templateID: template.id, templateName: template.name, templateIcon: template.icon,
                    templateColor: template.color, timing: SessionTiming(startedAt: env.clock.now, endedAt: env.clock.now.addingTimeInterval(600)),
                    now: env.clock.now, taskPriority: TaskPriority(isUrgent: urgent, isImportant: important))
        }
        let logs = [log(true, true), log(true, false), log(false, true), log(false, false)]

        func count(_ filter: TaskPriorityFilter?) -> Int {
            WorkLogQuery.filter(logs, with: WorkLogFilter(priority: filter)).count
        }
        #expect(count(nil) == 4)
        #expect(count(.urgent) == 2)
        #expect(count(.important) == 2)
        #expect(count(.urgentAndImportant) == 1)
        #expect(count(.neither) == 1)
        #expect(WorkLogFilter(priority: .urgent).isActive)
        #expect(WorkLogFilter().isActive == false)
    }

    // MARK: Analytics

    @Test("Analytics total each combination, and respect the date range")
    func analytics() throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate()
        let study = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"])
        let today = TestDates.date(2026, 9, 16, 9)
        let lastWeek = TestDates.date(2026, 9, 5, 9)

        func log(_ template: WorkTemplate, _ start: Date, minutes: Double, _ urgent: Bool, _ important: Bool) -> WorkLog {
            WorkLog(templateID: template.id, templateName: template.name, templateIcon: template.icon,
                    templateColor: template.color,
                    timing: SessionTiming(startedAt: start, endedAt: start.addingTimeInterval(minutes * 60)),
                    now: start, taskPriority: TaskPriority(isUrgent: urgent, isImportant: important))
        }
        let logs = [
            log(engineering, today, minutes: 60, true, true),
            log(engineering, today.addingTimeInterval(7200), minutes: 30, false, true),
            log(study, today.addingTimeInterval(14400), minutes: 20, true, false),
            log(study, today.addingTimeInterval(21600), minutes: 10, false, false),
            log(engineering, lastWeek, minutes: 300, true, true)   // outside the range
        ]
        let range = WorkAnalytics.dayInterval(containing: today)
        let inRange = WorkAnalytics.logs(logs, in: range)
        #expect(inRange.count == 4)

        let totals = WorkAnalytics.priorityTotals(inRange)
        #expect(totals.map(\.quadrant) == TaskPriorityQuadrant.allCases)
        #expect(totals[0].duration == 3600)
        #expect(totals[1].duration == 1200)
        #expect(totals[2].duration == 1800)
        #expect(totals[3].duration == 600)
        #expect(totals.map(\.sessionCount) == [1, 1, 1, 1])
        #expect(abs(totals[0].share - 3600.0 / 7200) < 1e-9)
        #expect(abs(totals.reduce(0) { $0 + $1.share } - 1) < 1e-9)

        let summary = WorkAnalytics.summary(inRange)
        #expect(summary.totalActiveDuration == 7200)
        #expect(summary.sessionCount == 4)
        #expect(summary.averageSessionDuration == 1800)
        #expect(summary.urgentDuration == 4800)          // 60m + 20m
        #expect(summary.importantDuration == 5400)       // 60m + 30m
        #expect(summary.urgentAndImportantDuration == 3600)
        #expect(summary.neitherDuration == 600)

        // Empty ranges report zeros rather than a misleading share.
        let empty = WorkAnalytics.priorityTotals([])
        #expect(empty.count == 4)
        #expect(empty.allSatisfy { $0.duration == 0 && $0.share == 0 && $0.sessionCount == 0 })
        #expect(WorkAnalytics.summary([]).averageSessionDuration == 0)

        let byTemplate = WorkAnalytics.templatePriorityTotals(inRange)
        #expect(byTemplate.map(\.template.name) == ["Software Engineering", "Study"])
        #expect(byTemplate[0].urgentDuration == 3600)
        #expect(byTemplate[0].importantDuration == 5400)
        #expect(byTemplate[1].urgentDuration == 1200)
        #expect(byTemplate[1].importantDuration == 0)
    }

    // MARK: Calendar

    @Test("Calendar event notes record the priority, and the title stays the template name")
    func calendarNotes() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work", priority: TaskPriority(isUrgent: true, isImportant: true))
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 40)
        let completion = try await env.sessionService.finish()
        #expect(completion.calendarOutcome?.succeeded == true)

        let saved = try #require(env.calendarProvider.saveCalls.last)
        #expect(saved.draft.title == "Software Engineering")
        #expect(saved.draft.notes.contains("Urgent: Yes · Important: Yes"))

        let neither = WorkLog(templateID: nil, templateName: "Quick", templateIcon: "bolt", templateColor: .white,
                              timing: SessionTiming(startedAt: env.clock.now, endedAt: env.clock.now), now: env.clock.now)
        #expect(CalendarService.eventNotes(for: neither, configuration: CalendarConfiguration())
            .contains("Urgent: No · Important: No"))
    }

    // MARK: Model helpers

    @Test("Quadrants map both ways and carry distinct symbols and labels")
    func quadrantModel() {
        for quadrant in TaskPriorityQuadrant.allCases {
            #expect(quadrant.priority.quadrant == quadrant)
            #expect(!quadrant.title.isEmpty)
            #expect(!quadrant.symbolName.isEmpty)
        }
        #expect(Set(TaskPriorityQuadrant.allCases.map(\.symbolName)).count == 4)
        #expect(Set(TaskPriorityQuadrant.allCases.map(\.color.hex)).count == 4)
        #expect(TaskPriority(isUrgent: true, isImportant: false).accessibilityLabel == "Urgent, Yes. Important, No.")
        #expect(TaskPriority.yesNo(true) == "Yes")
        #expect(TaskPriority.yesNo(false) == "No")
    }
}
