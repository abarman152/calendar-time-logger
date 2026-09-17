import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Change template of a completed work log")
struct TemplateReassignmentTests {
    @Test("Moves identity and default tags, keeps timing and notes, and updates the owned event")
    func reassign() async throws {
        let env = try TestEnvironment()
        let engineering = try env.makeTemplate(calendarIdentifier: "work")
        let writing = try env.makeTemplate(name: "Writing", icon: "pencil", tags: ["writing"])
        let session = try env.sessionService.start(template: engineering)
        try env.sessionService.updateActiveSession(tags: session.tags + ["urgent"])
        try env.sessionService.appendNote("Draft")
        env.clock.advance(minutes: 90)
        try await env.sessionService.finish()
        let eventID = try #require(session.calendarEventIdentifier)
        let timing = (session.startedAt, session.endedAt)

        let outcome = try await env.sessionService.reassignTemplate(of: session, to: writing)
        #expect(outcome == .updated(eventIdentifier: eventID))
        #expect(session.templateID == writing.id)
        #expect(session.templateName == "Writing")
        #expect(session.templateIcon == "pencil")
        #expect(session.tags == ["writing", "urgent"])
        #expect((session.startedAt, session.endedAt) == timing)
        #expect(session.notes.contains("Draft"))
        // The same owned event now carries the new title; no duplicate was created.
        #expect(env.calendarProvider.events.count == 1)
        #expect(env.calendarProvider.events[eventID]?.record.title == "Writing")
    }

    @Test("Sessions that aren't in Calendar stay out of Calendar")
    func notSynced() async throws {
        let env = try TestEnvironment()
        env.settings.calendarSyncEnabled = false
        let a = try env.makeTemplate()
        let b = try env.makeTemplate(name: "Study", icon: "book")
        let session = try env.sessionService.start(template: a)
        env.clock.advance(minutes: 10)
        try await env.sessionService.finish()
        env.settings.calendarSyncEnabled = true
        #expect(try await env.sessionService.reassignTemplate(of: session, to: b) == .skipped)
        #expect(env.calendarProvider.saveCalls.isEmpty)
        #expect(session.templateName == "Study")
    }

    @Test("Only completed sessions can be moved, and moving to the same template does nothing")
    func guards() async throws {
        let env = try TestEnvironment()
        let a = try env.makeTemplate()
        let b = try env.makeTemplate(name: "Study", icon: "book")
        let session = try env.sessionService.start(template: a)
        await #expect(throws: SessionError.self) { try await env.sessionService.reassignTemplate(of: session, to: b) }
        #expect(session.templateID == a.id)
        env.clock.advance(minutes: 10)
        try await env.sessionService.finish()
        let modified = session.modifiedAt
        #expect(try await env.sessionService.reassignTemplate(of: session, to: a) == .skipped)
        #expect(session.modifiedAt == modified)
    }
}
