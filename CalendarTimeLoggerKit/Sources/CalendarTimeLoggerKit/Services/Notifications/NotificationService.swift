import Foundation
import Observation

public enum NotificationAuthorization: String, Sendable {
    case notDetermined, denied, authorized

    public var displayName: String {
        switch self {
        case .notDetermined: "Not Requested"
        case .denied: "Off"
        case .authorized: "Allowed"
        }
    }
}

/// A platform-neutral notification request. `fireDate == nil` delivers now.
public struct NotificationRequest: Hashable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let fireDate: Date?

    public init(identifier: String, title: String, body: String, fireDate: Date? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

/// The boundary around UserNotifications.
@MainActor
public protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func add(_ request: NotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

/// Decides which notifications to deliver. Delivery respects the global
/// settings, the template's behavior, and system permission.
@MainActor
@Observable
public final class NotificationService {
    @ObservationIgnored private let scheduler: NotificationScheduling
    @ObservationIgnored private let preferences: () -> NotificationPreferences
    @ObservationIgnored private let now: () -> Date

    public private(set) var authorization: NotificationAuthorization = .notDetermined

    /// Reminders scheduled ahead for a running session.
    public static let reminderLookahead = 8

    public init(
        scheduler: NotificationScheduling,
        preferences: @escaping () -> NotificationPreferences,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.preferences = preferences
        self.now = now
    }

    public func refreshAuthorization() async {
        authorization = await scheduler.authorizationStatus()
    }

    /// Asks for permission only if it was never requested.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> NotificationAuthorization {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = await scheduler.requestAuthorization()
            await refreshAuthorization()
        }
        return authorization
    }

    // MARK: Session events

    public func sessionStarted(_ session: WorkSession, behavior: NotificationBehavior) async {
        let prefs = preferences()
        guard prefs.isEnabled else { return }
        let wantsStart = prefs.sessionStarted && behavior.notifyOnStart
        let wantsReminders = prefs.reminders && behavior.reminderIntervalMinutes != nil
        guard wantsStart || wantsReminders else { return }
        guard await requestAuthorizationIfNeeded() == .authorized else { return }

        if wantsStart {
            await deliver(Self.startedRequest(for: session))
        }
        await scheduleReminders(for: session, behavior: behavior)
    }

    public func sessionPaused(_ session: WorkSession) {
        cancelReminders(for: session)
    }

    public func sessionResumed(_ session: WorkSession, behavior: NotificationBehavior) async {
        await scheduleReminders(for: session, behavior: behavior)
    }

    public func sessionEnded(_ session: WorkSession) {
        cancelReminders(for: session)
    }

    public func sessionCompleted(_ log: WorkLog, behavior: NotificationBehavior, todayTotal: TimeInterval?) async {
        let prefs = preferences()
        guard prefs.isEnabled, prefs.sessionCompleted, behavior.notifyOnFinish else { return }
        guard await currentAuthorization() == .authorized else { return }
        await deliver(Self.completedRequest(for: log, todayTotal: prefs.includesTodayTotal ? todayTotal : nil))
    }

    public func calendarSyncFailed(_ log: WorkLog, error: CalendarSyncError) async {
        let prefs = preferences()
        guard prefs.isEnabled, prefs.calendarFailures else { return }
        guard await currentAuthorization() == .authorized else { return }
        await deliver(NotificationRequest(
            identifier: "calendar-failure-\(log.id.uuidString)",
            title: "Work saved, but not added to Calendar",
            body: "\(log.templateName): \(error.errorDescription ?? "Calendar sync failed.")"
        ))
    }

    // MARK: Reminders

    private func scheduleReminders(for session: WorkSession, behavior: NotificationBehavior) async {
        cancelReminders(for: session)
        let prefs = preferences()
        guard prefs.isEnabled, prefs.reminders, let minutes = behavior.reminderIntervalMinutes,
              session.state == .active else { return }
        guard await currentAuthorization() == .authorized else { return }
        for request in Self.reminderRequests(for: session, intervalMinutes: minutes, now: now()) {
            await deliver(request)
        }
    }

    public func cancelReminders(for session: WorkSession) {
        scheduler.removePendingRequests(withIdentifiers: Self.reminderIdentifiers(for: session.id))
    }

    // MARK: Request builders (pure, tested)

    public static func reminderIdentifiers(for sessionID: UUID) -> [String] {
        (1...reminderLookahead).map { "reminder-\(sessionID.uuidString)-\($0)" }
    }

    /// Reminders at each upcoming multiple of the interval of *active* time.
    /// Rescheduled on resume so paused time never counts.
    public static func reminderRequests(for session: WorkSession, intervalMinutes: Int, now: Date) -> [NotificationRequest] {
        guard intervalMinutes > 0, session.state == .active else { return [] }
        let interval = TimeInterval(intervalMinutes * 60)
        let active = session.activeDuration(at: now)
        let completedIntervals = Int((active / interval).rounded(.down))
        let identifiers = reminderIdentifiers(for: session.id)
        return (1...reminderLookahead).map { index in
            let target = interval * Double(completedIntervals + index)
            let fireDate = now.addingTimeInterval(target - active)
            return NotificationRequest(
                identifier: identifiers[index - 1],
                title: "Still working on \(session.templateName)?",
                body: "\(DurationFormatting.short(target)) of active work so far.",
                fireDate: fireDate
            )
        }
    }

    public static func startedRequest(for session: WorkSession) -> NotificationRequest {
        NotificationRequest(
            identifier: "started-\(session.id.uuidString)",
            title: "Started \(session.templateName)",
            body: "Timer is running. Finish Work when you’re done."
        )
    }

    public static func completedRequest(for log: WorkLog, todayTotal: TimeInterval?) -> NotificationRequest {
        let time = log.startedAt.formatted(date: .omitted, time: .shortened) + " – "
            + log.endedAt.formatted(date: .omitted, time: .shortened)
        var body = "\(time) · \(DurationFormatting.short(log.activeDuration)) active"
        if let todayTotal {
            body += "\nToday: \(DurationFormatting.short(todayTotal))"
        }
        return NotificationRequest(
            identifier: "completed-\(log.id.uuidString)",
            title: "Work Completed: \(log.templateName)",
            body: body
        )
    }

    private func currentAuthorization() async -> NotificationAuthorization {
        await refreshAuthorization()
        return authorization
    }

    private func deliver(_ request: NotificationRequest) async {
        // Notification failures are non-critical and never affect recorded work.
        try? await scheduler.add(request)
    }
}
