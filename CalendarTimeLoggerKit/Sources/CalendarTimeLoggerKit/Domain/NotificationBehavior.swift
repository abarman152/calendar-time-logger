import Foundation

/// Per-template notification behavior. Global settings can still turn each
/// category off (see `NotificationPreferences`).
public struct NotificationBehavior: Codable, Hashable, Sendable {
    public var notifyOnStart: Bool
    public var notifyOnFinish: Bool
    /// Remind after every N minutes of active work. `nil` disables reminders.
    public var reminderIntervalMinutes: Int?

    public static let reminderChoices: [Int] = [15, 30, 45, 60, 90, 120]

    public init(notifyOnStart: Bool = false, notifyOnFinish: Bool = true, reminderIntervalMinutes: Int? = nil) {
        self.notifyOnStart = notifyOnStart
        self.notifyOnFinish = notifyOnFinish
        self.reminderIntervalMinutes = reminderIntervalMinutes
    }

    public static let `default` = NotificationBehavior()

    private enum CodingKeys: String, CodingKey {
        case notifyOnStart, notifyOnFinish, reminderIntervalMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifyOnStart = try c.decodeIfPresent(Bool.self, forKey: .notifyOnStart) ?? false
        notifyOnFinish = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFinish) ?? true
        reminderIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderIntervalMinutes)
    }
}
