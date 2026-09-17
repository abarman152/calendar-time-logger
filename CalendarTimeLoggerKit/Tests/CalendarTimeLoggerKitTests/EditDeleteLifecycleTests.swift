import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

/// Edit and delete must be safe however they are reached: twice in a row, on a
/// model deleted elsewhere, across an `await`, and after a relaunch.
@MainActor
@Suite("Edit and delete lifecycle")
struct EditDeleteLifecycleTests {
    static func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ctl-edit-delete-\(UUID().uuidString).store")
    }

    static func remove(_ url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
    }

    /// Starts and finishes a 30-minute session from `template`.
    func completedSession(_ env: TestEnvironment, template: WorkTemplate) async throws -> WorkSession {
        let session = try env.sessionService.start(template: template)
        env.clock.advance(minutes: 30)
        _ = try await env.sessionService.finish()
        return session
    }

    @Test("A deleted model is no longer live, before and after the delete is saved")
    func liveness() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        let session = try await completedSession(env, template: template)
        #expect(template.isLive)
        #expect(session.isLive)

        env.persistence.context.delete(session)
        #expect(!session.isLive)
        try env.persistence.save()
        #expect(!session.isLive)

        try env.persistence.deleteTemplate(template)
        #expect(!template.isLive)
    }

    @Test("Deleting a work log twice, after a relaunch, deletes it once and doesn't fail")
    func deleteWorkLogTwice() async throws {
        let url = Self.storeURL()
        defer { Self.remove(url) }
        var keptID = UUID()
        do {
            let env = try TestEnvironment(persistence: try PersistenceService.open(url: url))
            let template = try env.makeTemplate()
            keptID = try await completedSession(env, template: template).id
            _ = try await completedSession(env, template: template)
        }

        // Fetched after a relaunch, so the models start as faults, as in the app.
        let env = try TestEnvironment(persistence: try PersistenceService.open(url: url))
        let deleted = try #require(try env.persistence.completedSessions().first { $0.id != keptID })
        try env.sessionService.delete(deleted, removingCalendarEvent: false)
        try env.sessionService.delete(deleted, removingCalendarEvent: true)

        #expect(try env.persistence.completedSessions().map(\.id) == [keptID])
    }

    @Test("Deleting a work log with its Calendar event removes only that event")
    func deleteWorkLogWithEvent() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work")
        let kept = try await completedSession(env, template: template)
        let deleted = try await completedSession(env, template: template)
        let deletedEvent = try #require(deleted.calendarEventIdentifier)

        try env.sessionService.delete(deleted, removingCalendarEvent: true)

        #expect(try env.persistence.completedSessions().map(\.id) == [kept.id])
        #expect(env.calendarProvider.removedIdentifiers == [deletedEvent])
        #expect(kept.calendarEventIdentifier.flatMap { env.calendarProvider.events[$0] } != nil)
    }

    @Test("Deleting a template twice deletes it once and doesn't fail")
    func deleteTemplateTwice() throws {
        let env = try TestEnvironment()
        let kept = try env.makeTemplate(name: "Study", icon: "book")
        let deleted = try env.makeTemplate()
        try env.persistence.deleteTemplate(deleted)
        try env.persistence.deleteTemplate(deleted)
        #expect(try env.persistence.templates().map(\.id) == [kept.id])
    }

    @Test("Editing, moving, or syncing a deleted work log is refused without reading it")
    func actOnDeletedWorkLog() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(calendarIdentifier: "work")
        let other = try env.makeTemplate(name: "Study", icon: "book")
        let session = try await completedSession(env, template: template)
        let edit = SessionEdit(session: session)
        env.calendarProvider.saveCalls.removeAll()

        try env.sessionService.delete(session, removingCalendarEvent: false)

        await #expect(throws: SessionError.workLogDeleted) { try await env.sessionService.edit(session, with: edit) }
        await #expect(throws: SessionError.workLogDeleted) { try await env.sessionService.reassignTemplate(of: session, to: other) }
        #expect(await env.sessionService.retryCalendarSync(session) == .skipped)
        #expect(throws: Never.self) { try env.calendarService.removeEvent(for: session) }
        #expect(env.calendarProvider.saveCalls.isEmpty)
    }

    @Test("Saving or duplicating a deleted template is refused")
    func actOnDeletedTemplate() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        var draft = template.draft
        draft.name = "Renamed"
        try env.persistence.deleteTemplate(template)

        #expect(throws: PersistenceError.itemDeleted) { try env.persistence.updateTemplate(template, with: draft) }
        #expect(throws: PersistenceError.itemDeleted) { try env.persistence.duplicateTemplate(template) }
        #expect(try env.persistence.templates().isEmpty)
        #expect(PersistenceError.itemDeleted.recoverySuggestion != nil)
        #expect(SessionError.workLogDeleted.recoverySuggestion != nil)
    }

    @Test("Deleting the new work log while Calendar asks for access doesn't crash finishing")
    func deleteDuringCalendarPrompt() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.authorization = .notDetermined
        let template = try env.makeTemplate(calendarIdentifier: "work")
        let session = try env.sessionService.start(template: template)
        env.clock.advance(minutes: 45)
        env.calendarProvider.onRequestFullAccess = {
            try? env.sessionService.delete(session, removingCalendarEvent: false)
        }

        let completion = try await env.sessionService.finish()

        #expect(completion.log.id == session.id)
        #expect(completion.calendarOutcome == nil)
        #expect(env.calendarProvider.saveCalls.isEmpty)
        #expect(try env.persistence.completedSessions().isEmpty)
    }

    @Test("Deleting a template in use keeps the running session and its work log")
    func deleteTemplateInUse() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(category: "Development", priority: TaskPriority(isUrgent: true, isImportant: false))
        let session = try env.sessionService.start(template: template)
        env.clock.advance(minutes: 20)
        try env.persistence.deleteTemplate(template)

        #expect(env.sessionService.activeSession === session)
        env.clock.advance(minutes: 10)
        let completion = try await env.sessionService.finish()

        #expect(completion.log.templateName == "Software Engineering")
        #expect(completion.log.category == "Development")
        #expect(completion.log.taskPriority == TaskPriority(isUrgent: true, isImportant: false))
        #expect(completion.log.activeDuration == 30 * 60)
        #expect(try env.persistence.completedSessions().map(\.id) == [session.id])
    }

    @Test("Edits and deletes of templates and work logs survive a relaunch; unrelated items don't change")
    func persistsAcrossRelaunch() async throws {
        let url = Self.storeURL()
        defer { Self.remove(url) }
        let start = TestDates.date(2026, 9, 15, 9)
        var ids: (editedTemplate: UUID, deletedTemplate: UUID, keptLog: UUID, editedLog: UUID, deletedLog: UUID)

        do {
            let env = try TestEnvironment(clock: TestClock(start), persistence: try PersistenceService.open(url: url))
            let edited = try env.makeTemplate(name: "Study", icon: "book", category: "Education")
            let deleted = try env.makeTemplate()
            let kept = try await completedSession(env, template: edited)
            let editedLog = try await completedSession(env, template: deleted)
            let deletedLog = try await completedSession(env, template: deleted)
            ids = (edited.id, deleted.id, kept.id, editedLog.id, deletedLog.id)

            var draft = edited.draft
            draft.name = "Deep Study"
            draft.category = "Research"
            draft.taskPriority = TaskPriority(isUrgent: false, isImportant: true)
            try env.persistence.updateTemplate(edited, with: draft)

            var edit = SessionEdit(session: editedLog)
            edit.notes = "Corrected"
            edit.tags = ["fixed"]
            edit.taskPriority = TaskPriority(isUrgent: true, isImportant: true)
            edit.category = "Design"
            _ = try await env.sessionService.edit(editedLog, with: edit)

            try env.sessionService.delete(deletedLog, removingCalendarEvent: false)
            try env.persistence.deleteTemplate(deleted)
        }

        let reopened = try PersistenceService.open(url: url)
        let templates = try reopened.templates()
        #expect(templates.map(\.id) == [ids.editedTemplate])
        #expect(templates.first?.name == "Deep Study")
        #expect(templates.first?.category == "Research")
        #expect(templates.first?.taskPriority == TaskPriority(isUrgent: false, isImportant: true))

        let logs = try reopened.completedSessions()
        #expect(Set(logs.map(\.id)) == [ids.keptLog, ids.editedLog])
        #expect(reopened.session(id: ids.deletedLog) == nil)

        let editedLog = try #require(reopened.session(id: ids.editedLog))
        #expect(editedLog.notes == "Corrected")
        #expect(editedLog.tags == ["fixed"])
        #expect(editedLog.category == "Design")
        #expect(editedLog.taskPriority == TaskPriority(isUrgent: true, isImportant: true))
        #expect(editedLog.templateName == "Software Engineering")

        // Editing the template changed no recorded work.
        let keptLog = try #require(reopened.session(id: ids.keptLog))
        #expect(keptLog.templateName == "Study")
        #expect(keptLog.category == "Education")
        #expect(keptLog.taskPriority == .default)
        #expect(keptLog.notes.isEmpty)
    }
}
