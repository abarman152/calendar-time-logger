import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Session engine")
struct SessionServiceTests {
    @Test("Start creates and persists an active session without a Calendar event")
    func startSession() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        let session = try env.sessionService.start(template: template)

        #expect(session.state == .active)
        #expect(session.startedAt == env.clock.now)
        #expect(session.templateID == template.id)
        #expect(session.templateName == "Software Engineering")
        #expect(session.tags == ["coding", "development"])
        #expect(env.sessionService.activeSession === session)
        #expect(try env.persistence.openSessions().map(\.id) == [session.id])
        // Rule 1: starting never touches Calendar.
        #expect(env.calendarProvider.saveCalls.isEmpty)
        #expect(session.calendarEventIdentifier == nil)
    }

    @Test("Only one open session is allowed")
    func singleActiveSession() throws {
        let env = try TestEnvironment()
        let first = try env.makeTemplate()
        let second = try env.makeTemplate(name: "Study", icon: "book")
        try env.sessionService.start(template: first)
        #expect(throws: SessionError.sessionAlreadyActive(templateName: "Software Engineering")) {
            try env.sessionService.start(template: second)
        }
    }

    @Test("Pause and resume record timestamps and exclude paused time")
    func pauseResume() throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        env.clock.set(11, 15)
        try env.sessionService.pause()
        #expect(session.state == .paused)
        env.clock.set(11, 40)
        try env.sessionService.resume()
        #expect(session.state == .active)
        #expect(session.pauses.count == 1)
        #expect(session.pauses[0].end == env.clock.now)
        env.clock.set(12, 0)
        // 10:00–11:15 and 11:40–12:00 are active.
        #expect(session.activeDuration(at: env.clock.now) == TimeInterval(95 * 60))
        #expect(session.pausedDuration(at: env.clock.now) == 25 * 60)
    }

    @Test("Finish Work completes, keeps both durations, and creates the Calendar event")
    func finishWork() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate(calendarIdentifier: "work"))
        env.clock.set(11, 15); try env.sessionService.pause()
        env.clock.set(11, 40); try env.sessionService.resume()
        env.clock.set(12, 24)

        let completion = try await env.sessionService.finish()

        #expect(session.state == .completed)
        #expect(session.endedAt == env.clock.now)
        #expect(completion.log.wallClockDuration == 2 * 3600 + 24 * 60)
        #expect(completion.log.activeDuration == 3600 + 59 * 60)
        #expect(completion.log.pausedDuration == 25 * 60)
        #expect(completion.calendarOutcome == .created(eventIdentifier: "event-1"))
        #expect(completion.calendarName == "Work")
        #expect(env.sessionService.activeSession == nil)
        #expect(session.calendarSyncStatus == .synced)
        #expect(session.calendarEventIdentifier == "event-1")
        #expect(session.eventCalendarIdentifier == "work")

        // The event spans the real session interval.
        let draft = try #require(env.calendarProvider.saveCalls.first?.draft)
        #expect(draft.title == "Software Engineering")
        #expect(draft.startDate == TestDates.date(2026, 9, 15, 10, 0))
        #expect(draft.endDate == TestDates.date(2026, 9, 15, 12, 24))
    }

    @Test("Finishing while paused closes the pause at the finish time")
    func finishWhilePaused() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        env.clock.set(10, 30); try env.sessionService.pause()
        env.clock.set(11, 0)
        try await env.sessionService.finish()
        #expect(session.pauses == [PauseInterval(start: TestDates.date(2026, 9, 15, 10, 30), end: TestDates.date(2026, 9, 15, 11, 0))])
        #expect(session.activeDuration(at: .distantFuture) == 30 * 60)
    }

    @Test("Cancel keeps a cancelled record and never syncs")
    func cancelSession() throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        env.clock.advance(minutes: 10)
        try env.sessionService.cancel()
        #expect(session.state == .cancelled)
        #expect(session.endedAt == env.clock.now)
        #expect(env.sessionService.activeSession == nil)
        #expect(env.calendarProvider.saveCalls.isEmpty)
        #expect(try env.persistence.completedSessions().isEmpty)
    }

    @Test("Invalid transitions throw and leave the session unchanged")
    func invalidTransitions() async throws {
        let env = try TestEnvironment()
        #expect(throws: SessionError.noActiveSession) { try env.sessionService.pause() }
        #expect(throws: SessionError.noActiveSession) { try env.sessionService.resume() }

        let session = try env.sessionService.start(template: env.makeTemplate())
        #expect(throws: SessionError.invalidTransition(InvalidSessionTransition(state: .active, event: .resume))) {
            try env.sessionService.resume()
        }
        try env.sessionService.pause()
        #expect(throws: SessionError.invalidTransition(InvalidSessionTransition(state: .paused, event: .pause))) {
            try env.sessionService.pause()
        }
        try await env.sessionService.finish()
        // A completed session can't be paused, resumed, or finished again.
        await #expect(throws: SessionError.noActiveSession) { try await env.sessionService.finish() }
        #expect(throws: SessionError.noActiveSession) { try env.sessionService.pause() }
        #expect(session.state == .completed)
    }

    @Test("Change Template keeps timing and swaps identity and default tags")
    func changeTemplate() throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate()
        let study = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"])
        let session = try env.sessionService.start(template: engineering)
        try env.sessionService.updateActiveSession(tags: session.tags + ["urgent"])
        env.clock.advance(minutes: 20)
        try env.sessionService.changeTemplate(to: study)
        #expect(session.templateID == study.id)
        #expect(session.templateName == "Study")
        #expect(session.templateIcon == "book")
        #expect(session.tags == ["learning", "urgent"])
        #expect(session.startedAt == TestDates.date(2026, 9, 15, 10, 0))
        #expect(session.activeDuration(at: env.clock.now) == TimeInterval(20 * 60))
    }

    @Test("Notes can be appended to the active session")
    func appendNote() throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        try env.sessionService.appendNote("Fixed the parser")
        try env.sessionService.appendNote("  ")
        #expect(session.notes.hasSuffix("Fixed the parser"))
        #expect(session.notes.split(separator: "\n").count == 1)
    }

    @Test("Recording is refused when the on-disk store couldn't be opened")
    func storageUnavailableGuard() throws {
        let healthy = try PersistenceService.inMemory()
        let degraded = PersistenceService(container: healthy.container, storeError: .storeUnavailable("Test"))
        let env = try TestEnvironment(persistence: degraded)
        let template = try env.makeTemplate()
        #expect(!env.sessionService.canRecordWork)
        #expect(throws: SessionError.storageUnavailable) { try env.sessionService.start(template: template) }
        #expect(try env.persistence.openSessions().isEmpty)
    }

    @Test("Editing a completed session updates the owned Calendar event")
    func editCompletedSession() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate(calendarIdentifier: "work"))
        env.clock.set(12, 0)
        try await env.sessionService.finish()
        env.clock.set(13, 0)

        var edit = SessionEdit(session: session)
        edit.endedAt = TestDates.date(2026, 9, 15, 11, 30)
        edit.notes = "Shipped it"
        let outcome = try await env.sessionService.edit(session, with: edit)

        #expect(outcome == .updated(eventIdentifier: "event-1"))
        #expect(env.calendarProvider.saveCalls.last?.existing == "event-1")
        #expect(env.calendarProvider.events["event-1"]?.record.endDate == edit.endedAt)
        #expect(env.calendarProvider.events["event-1"]?.notes.contains("Shipped it") == true)
    }

    @Test("Edits with invalid times are rejected")
    func invalidEdit() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        env.clock.set(11, 0)
        try await env.sessionService.finish()
        var edit = SessionEdit(session: session)
        edit.endedAt = edit.startedAt.addingTimeInterval(-60)
        await #expect(throws: SessionError.self) { try await env.sessionService.edit(session, with: edit) }
        edit.endedAt = env.clock.now.addingTimeInterval(3600)
        await #expect(throws: SessionError.self) { try await env.sessionService.edit(session, with: edit) }
        #expect(session.endedAt == TestDates.date(2026, 9, 15, 11, 0))
    }

    @Test("Deleting a session can remove its owned event")
    func deleteSession() async throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate(calendarIdentifier: "work"))
        env.clock.set(11, 0)
        try await env.sessionService.finish()
        try env.sessionService.delete(session, removingCalendarEvent: true)
        #expect(env.calendarProvider.removedIdentifiers == ["event-1"])
        #expect(try env.persistence.completedSessions().isEmpty)
    }

    @Test("Pause on system sleep only pauses running sessions")
    func pauseForSleep() throws {
        let env = try TestEnvironment()
        #expect(!env.sessionService.pauseForSystemSleep())
        try env.sessionService.start(template: env.makeTemplate())
        #expect(env.sessionService.pauseForSystemSleep())
        #expect(env.sessionService.activeSession?.state == .paused)
        #expect(!env.sessionService.pauseForSystemSleep())
    }
}
