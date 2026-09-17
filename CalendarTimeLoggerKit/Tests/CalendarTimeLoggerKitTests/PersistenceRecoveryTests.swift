import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Persistence and recovery")
struct PersistenceRecoveryTests {
    @Test("An active session is saved and reloaded after relaunch")
    func reloadActiveSession() throws {
        let env = try TestEnvironment()
        let session = try env.sessionService.start(template: env.makeTemplate())
        let id = session.id

        // Read through a separate context to prove the data was saved, not just held in memory.
        let freshContext = ModelContext(env.persistence.container)
        let stored = try freshContext.fetch(FetchDescriptor<WorkSession>())
        #expect(stored.map(\.id) == [id])
        #expect(stored.first?.state == .active)

        env.clock.advance(minutes: 90)
        env.relaunch()
        #expect(env.sessionService.activeSession?.id == id)
        #expect(env.sessionService.pendingRecovery?.id == id)
        #expect(env.sessionService.activeSession?.activeDuration(at: env.clock.now) == TimeInterval(90 * 60))
    }

    @Test("Recovered session can be resumed")
    func resumeRecovered() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: env.makeTemplate())
        env.clock.advance(minutes: 5)
        try env.sessionService.pause()
        env.relaunch()
        try await env.sessionService.resolveRecovery(.resume)
        #expect(env.sessionService.pendingRecovery == nil)
        #expect(env.sessionService.activeSession?.state == .active)
    }

    @Test("Recovered session can be finished and synced")
    func finishRecovered() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: env.makeTemplate())
        env.clock.advance(minutes: 60)
        env.relaunch()
        try await env.sessionService.resolveRecovery(.finishNow)
        let completed = try env.persistence.completedSessions()
        #expect(completed.count == 1)
        #expect(completed.first?.activeDuration(at: .distantFuture) == 3600)
        #expect(completed.first?.calendarSyncStatus == .synced)
        #expect(env.sessionService.activeSession == nil)
    }

    @Test("Recovered session can be finished at the last heartbeat")
    func finishAtLastSeen() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: env.makeTemplate())
        env.clock.advance(minutes: 30)
        env.sessionService.recordHeartbeat()
        env.clock.advance(minutes: 300) // App crashed; the user returns hours later.
        env.relaunch()
        try await env.sessionService.resolveRecovery(.finishAtLastSeen)
        let completed = try #require(try env.persistence.completedSessions().first)
        #expect(completed.activeDuration(at: .distantFuture) == TimeInterval(30 * 60))
    }

    @Test("Recovered session can be cancelled")
    func cancelRecovered() async throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: env.makeTemplate())
        env.relaunch()
        try await env.sessionService.resolveRecovery(.cancel)
        #expect(env.sessionService.activeSession == nil)
        #expect(try env.persistence.openSessions().isEmpty)
    }

    @Test("Sessions survive template deletion via their snapshot")
    func templateDeletionKeepsSessions() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 45)
        try await env.sessionService.finish()
        try env.persistence.deleteTemplate(template)
        let log = WorkLog(session: try #require(try env.persistence.completedSessions().first))
        #expect(log.templateName == "Software Engineering")
        #expect(log.templateIcon == "laptopcomputer")
        #expect(log.activeDuration == 45 * 60)
    }

    @Test("Default templates are seeded once")
    func seedingOnce() throws {
        let env = try TestEnvironment()
        try env.persistence.seedDefaultTemplatesIfNeeded(defaults: env.defaults)
        #expect(try env.persistence.templates().map(\.name) == ["Software Engineering", "Study", "Research", "Writing", "Design"])
        for template in try env.persistence.templates() { try env.persistence.deleteTemplate(template) }
        try env.persistence.seedDefaultTemplatesIfNeeded(defaults: env.defaults)
        #expect(try env.persistence.templates().isEmpty)
    }

    @Test("Settings persist in UserDefaults")
    func settingsPersist() throws {
        let env = try TestEnvironment()
        env.settings.defaultCalendarIdentifier = "work"
        env.settings.menuBarShowsSeconds = false
        env.settings.appearance = .dark
        let reloaded = SettingsStore(defaults: env.defaults)
        #expect(reloaded.defaultCalendarIdentifier == "work")
        #expect(!reloaded.menuBarShowsSeconds)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.calendarSyncEnabled)
    }
}
