import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Notifications")
struct NotificationServiceTests {
    func activeSession(_ env: TestEnvironment, behavior: NotificationBehavior = .default) throws -> WorkSession {
        let session = WorkSession(templateID: UUID(), templateName: "Research", templateIcon: "flask",
                                  templateColorHex: "#30D158", startedAt: env.clock.now)
        env.persistence.context.insert(session)
        return session
    }

    @Test("Start notification respects template and global settings")
    func startNotification() async throws {
        let env = try TestEnvironment()
        let session = try activeSession(env)

        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: false))
        #expect(env.notificationScheduler.added.isEmpty)

        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: true))
        #expect(env.notificationScheduler.added.map(\.identifier) == ["started-\(session.id.uuidString)"])

        env.settings.notifySessionStarted = false
        env.notificationScheduler.added.removeAll()
        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: true))
        #expect(env.notificationScheduler.added.isEmpty)
    }

    @Test("Master switch disables everything and permission isn't requested")
    func masterSwitch() async throws {
        let env = try TestEnvironment()
        env.settings.notificationsEnabled = false
        env.notificationScheduler.status = .notDetermined
        let session = try activeSession(env)
        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: true, reminderIntervalMinutes: 30))
        #expect(env.notificationScheduler.added.isEmpty)
        #expect(env.notificationScheduler.requestCount == 0)
    }

    @Test("Permission is requested once, only when a notification is wanted")
    func permissionRequest() async throws {
        let env = try TestEnvironment()
        env.notificationScheduler.status = .notDetermined
        let session = try activeSession(env)
        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: false))
        #expect(env.notificationScheduler.requestCount == 0)
        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: true))
        #expect(env.notificationScheduler.requestCount == 1)
        #expect(env.notificationScheduler.added.count == 1)
    }

    @Test("Denied permission delivers nothing")
    func permissionDenied() async throws {
        let env = try TestEnvironment()
        env.notificationScheduler.status = .denied
        let session = try activeSession(env)
        await env.notificationService.sessionStarted(session, behavior: NotificationBehavior(notifyOnStart: true, reminderIntervalMinutes: 30))
        let log = WorkLog(session: session, now: env.clock.now)
        await env.notificationService.sessionCompleted(log, behavior: .default, todayTotal: 3600)
        #expect(env.notificationScheduler.added.isEmpty)
    }

    @Test("Reminders fire at multiples of active time")
    func reminderSchedule() throws {
        let env = try TestEnvironment()
        let session = try activeSession(env)
        // 20 minutes active, then a 10 minute pause, then resumed at 10:30.
        session.pauses = [PauseInterval(start: env.clock.now.addingTimeInterval(20 * 60), end: env.clock.now.addingTimeInterval(30 * 60))]
        let now = env.clock.now.addingTimeInterval(30 * 60)
        let requests = NotificationService.reminderRequests(for: session, intervalMinutes: 30, now: now)
        #expect(requests.count == NotificationService.reminderLookahead)
        // 10 more minutes of active work reaches the 30 minute mark.
        #expect(requests[0].fireDate == now.addingTimeInterval(10 * 60))
        #expect(requests[1].fireDate == now.addingTimeInterval(40 * 60))
        #expect(requests[0].body.contains("30m"))
        #expect(requests[1].body.contains("1h"))
    }

    @Test("No reminders for paused sessions; pausing cancels them")
    func remindersCancelledOnPause() async throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(behavior: NotificationBehavior(reminderIntervalMinutes: 60))
        let session = try env.sessionService.start(template: template)
        await env.notificationService.sessionResumed(session, behavior: template.notificationBehavior)
        #expect(env.notificationScheduler.added.filter { $0.identifier.hasPrefix("reminder-") }.count == NotificationService.reminderLookahead)

        try env.sessionService.pause()
        #expect(Set(env.notificationScheduler.removed).isSuperset(of: NotificationService.reminderIdentifiers(for: session.id)))
        #expect(NotificationService.reminderRequests(for: session, intervalMinutes: 60, now: env.clock.now).isEmpty)
    }

    @Test("Completion notification includes today's total when enabled")
    func completion() async throws {
        let env = try TestEnvironment()
        let session = try activeSession(env)
        env.clock.advance(minutes: 90)
        session.endedAt = env.clock.now
        session.state = .completed
        let log = WorkLog(session: session)

        await env.notificationService.sessionCompleted(log, behavior: .default, todayTotal: 4 * 3600 + 54 * 60)
        #expect(env.notificationScheduler.added.last?.title == "Work Completed: Research")
        #expect(env.notificationScheduler.added.last?.body.contains("Today: 4h 54m") == true)

        env.settings.includesTodayTotal = false
        await env.notificationService.sessionCompleted(log, behavior: .default, todayTotal: 3600)
        #expect(env.notificationScheduler.added.last?.body.contains("Today") == false)

        await env.notificationService.sessionCompleted(log, behavior: NotificationBehavior(notifyOnFinish: false), todayTotal: nil)
        #expect(env.notificationScheduler.added.count == 2)
    }

    @Test("Calendar failures notify when enabled")
    func calendarFailure() async throws {
        let env = try TestEnvironment()
        env.calendarProvider.authorization = .denied
        let template = try env.makeTemplate()
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 30)
        try await env.sessionService.finish()
        #expect(env.notificationScheduler.added.contains { $0.identifier.hasPrefix("calendar-failure-") })
    }
}
