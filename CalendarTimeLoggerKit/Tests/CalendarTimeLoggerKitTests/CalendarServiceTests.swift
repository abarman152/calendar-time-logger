import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Calendar integration")
struct CalendarServiceTests {
    /// Starts and finishes a one-hour session, returning it.
    func completedSession(_ env: TestEnvironment, calendar: String? = nil, notes: String = "") async throws -> (WorkSession, SessionCompletion) {
        let session = try env.sessionService.start(template: env.makeTemplate(calendarIdentifier: calendar))
        if !notes.isEmpty { try env.sessionService.updateActiveSession(notes: notes) }
        env.clock.advance(minutes: 60)
        let completion = try await env.sessionService.finish()
        return (session, completion)
    }

    @Test("Discovers calendars only with full access")
    func discovery() throws {
        let env = try TestEnvironment()
        #expect(env.calendarService.availableCalendars.map(\.title) == ["Work", "Personal", "University", "Holidays"])
        #expect(env.calendarService.writableCalendars.count == 3)
        env.calendarProvider.authorization = .denied
        env.calendarService.refresh()
        #expect(env.calendarService.availableCalendars.isEmpty)
    }

    @Test("Calendar resolution: session → template → global default → system default")
    func selection() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        let session = try env.sessionService.start(template: template)
        #expect(env.calendarService.resolvedCalendarIdentifier(for: session) == "personal")

        env.settings.defaultCalendarIdentifier = "university"
        #expect(env.calendarService.resolvedCalendarIdentifier(for: session) == "university")

        var draft = template.draft
        draft.calendarIdentifier = "work"
        try env.persistence.updateTemplate(template, with: draft)
        #expect(env.calendarService.resolvedCalendarIdentifier(for: session) == "work")

        try env.sessionService.updateActiveSession(calendarIdentifier: .some("personal"))
        #expect(env.calendarService.resolvedCalendarIdentifier(for: session) == "personal")
    }

    @Test("Creates an event with useful notes and an ownership URL")
    func eventCreation() async throws {
        let env = try TestEnvironment()
        let (session, completion) = try await completedSession(env, calendar: "work", notes: "Refactored sync")
        #expect(completion.calendarOutcome == .created(eventIdentifier: "event-1"))
        let stored = try #require(env.calendarProvider.events["event-1"])
        #expect(stored.record.calendarIdentifier == "work")
        #expect(CalendarOwnership.sessionID(from: stored.record.url) == session.id)
        #expect(stored.notes.contains("Recorded with Calendar Time Logger"))
        #expect(stored.notes.contains("Template: Software Engineering"))
        #expect(stored.notes.contains("Active work: 1h"))
        #expect(stored.notes.contains("Tags: #coding #development"))
        #expect(stored.notes.contains("Refactored sync"))
        // Internal identifiers stay out of the human-readable notes.
        #expect(!stored.notes.contains(session.id.uuidString))
    }

    @Test("Notes and tags can be excluded from events")
    func eventNotesRespectSettings() async throws {
        let env = try TestEnvironment()
        env.settings.includesNotesInEvents = false
        env.settings.includesTagsInEvents = false
        _ = try await completedSession(env, notes: "Private detail")
        let notes = try #require(env.calendarProvider.events["event-1"]?.notes)
        #expect(!notes.contains("Private detail"))
        #expect(!notes.contains("#coding"))
    }

    @Test("Syncing again updates the same owned event")
    func eventUpdate() async throws {
        let env = try TestEnvironment()
        let (session, _) = try await completedSession(env)
        session.notes = "Updated"
        let outcome = await env.calendarService.sync(session)
        #expect(outcome == .updated(eventIdentifier: "event-1"))
        #expect(env.calendarProvider.events.count == 1)
    }

    @Test("Permission denied keeps the work log and records an actionable failure")
    func permissionFailure() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.authorization = .denied
        let (session, completion) = try await completedSession(env)
        #expect(completion.calendarOutcome == .failed(.accessNotGranted(.denied)))
        #expect(session.state == .completed)
        #expect(try env.persistence.completedSessions().count == 1)
        #expect(session.calendarSyncStatus == .failed)
        #expect(session.calendarSyncMessage?.contains("System Settings") == true)
        #expect(env.calendarProvider.requestCount == 0)
    }

    @Test("Access is requested on the first finish only when never requested")
    func contextualPermissionRequest() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.authorization = .notDetermined
        env.calendarProvider.authorizationAfterRequest = .fullAccess
        let (_, completion) = try await completedSession(env)
        #expect(env.calendarProvider.requestCount == 1)
        #expect(completion.calendarOutcome?.succeeded == true)
    }

    @Test("Write-only access is reported as insufficient")
    func writeOnlyAccess() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.authorization = .writeOnly
        let (_, completion) = try await completedSession(env)
        #expect(completion.calendarOutcome == .failed(.accessNotGranted(.writeOnly)))
    }

    @Test("Event creation failure keeps the work log")
    func creationFailure() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.saveError = .operationFailed("Disk full")
        let (session, completion) = try await completedSession(env)
        #expect(completion.calendarOutcome == .failed(.saveFailed("Disk full")))
        #expect(session.state == .completed)
        #expect(session.calendarEventIdentifier == nil)
        #expect(try env.persistence.completedSessions().first?.id == session.id)

        env.calendarProvider.saveError = nil
        #expect(await env.sessionService.retryAllCalendarSyncs() == 1)
        #expect(session.calendarSyncStatus == .synced)
    }

    @Test("A missing calendar fails instead of silently using another calendar")
    func missingCalendar() async throws {
        let env = try TestEnvironment()
        let (session, completion) = try await completedSession(env, calendar: "deleted-calendar")
        #expect(completion.calendarOutcome == .failed(.calendarNotFound))
        #expect(session.calendarSyncStatus == .failed)
        #expect(env.calendarProvider.saveCalls.isEmpty)
    }

    @Test("Read-only calendars are rejected")
    func readOnlyCalendar() async throws {
        let env = try TestEnvironment()
        let (_, completion) = try await completedSession(env, calendar: "holidays")
        #expect(completion.calendarOutcome == .failed(.calendarReadOnly("Holidays")))
    }

    @Test("Sync disabled writes nothing")
    func syncDisabled() async throws {
        let env = try TestEnvironment()
        env.settings.calendarSyncEnabled = false
        let (session, completion) = try await completedSession(env)
        #expect(completion.calendarOutcome == .skipped)
        #expect(session.calendarSyncStatus == .notSynced)
        #expect(env.calendarProvider.saveCalls.isEmpty)
    }

    @Test("Unowned events are never modified")
    func eventOwnership() async throws {
        let env = try TestEnvironment()
        let (session, _) = try await completedSession(env)
        // Point the session at an event the app doesn't own.
        env.calendarProvider.insertForeignEvent(identifier: "foreign", url: URL(string: "https://example.com"))
        session.calendarEventIdentifier = "foreign"

        // The session's own event is found by its ownership URL and updated.
        var outcome = await env.calendarService.sync(session)
        #expect(outcome == .updated(eventIdentifier: "event-1"))
        #expect(env.calendarProvider.saveCalls.last?.existing == "event-1")
        #expect(env.calendarProvider.events["foreign"]?.record.title == "Dentist")

        // With no owned event left, a new one is created; the foreign event is still untouched.
        env.calendarProvider.events.removeValue(forKey: "event-1")
        session.calendarEventIdentifier = "foreign"
        outcome = await env.calendarService.sync(session)
        #expect(outcome == .created(eventIdentifier: "event-2"))
        #expect(env.calendarProvider.saveCalls.last?.existing == nil)
        #expect(env.calendarProvider.events["foreign"]?.record.title == "Dentist")

        session.calendarEventIdentifier = "foreign"
        #expect(throws: CalendarSyncError.eventNotOwned) { try env.calendarService.removeEvent(for: session) }
        #expect(env.calendarProvider.events["foreign"] != nil)
    }

    @Test("Events owned by another session are not treated as owned")
    func ownershipIsPerSession() async throws {
        let env = try TestEnvironment()
        let (session, _) = try await completedSession(env)
        let other = CalendarOwnership.url(for: UUID())
        env.calendarProvider.insertForeignEvent(identifier: "other", url: other)
        let record = try #require(env.calendarProvider.event(withIdentifier: "other"))
        #expect(!env.calendarService.isOwned(record, by: session))
        #expect(CalendarOwnership.sessionID(from: URL(string: "https://example.com/session/\(session.id)")) == nil)
    }

    @Test("A changed event identifier is re-linked instead of duplicating the event")
    func identifierDrift() async throws {
        let env = try TestEnvironment()
        let (session, _) = try await completedSession(env)
        env.calendarProvider.reassignIdentifier("event-1", to: "server-42")

        #expect(env.calendarService.reconcile([session]) == 1)
        #expect(session.calendarEventIdentifier == "server-42")
        #expect(session.calendarSyncStatus == .synced)

        env.calendarProvider.reassignIdentifier("server-42", to: "server-43")
        session.notes = "Edited"
        let outcome = await env.calendarService.sync(session)
        #expect(outcome == .updated(eventIdentifier: "server-43"))
        #expect(env.calendarProvider.events.count == 1)

        env.calendarProvider.reassignIdentifier("server-43", to: "server-44")
        try env.calendarService.removeEvent(for: session)
        #expect(env.calendarProvider.events.isEmpty)
        #expect(session.calendarEventIdentifier == nil)
    }

    @Test("Reconciliation marks events deleted in Calendar")
    func reconciliation() async throws {
        let env = try TestEnvironment()
        let (session, _) = try await completedSession(env)
        env.calendarProvider.events.removeAll()
        #expect(env.calendarService.reconcile([session]) == 1)
        #expect(session.calendarSyncStatus == .eventMissing)
        #expect(session.calendarEventIdentifier == nil)
        #expect(session.state == .completed)
    }
}
