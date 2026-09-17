import Foundation

/// App-wide Calendar behavior.
public struct CalendarConfiguration: Hashable, Sendable {
    public var isSyncEnabled: Bool
    /// Global default calendar. `nil` means “use the system default calendar”.
    public var defaultCalendarIdentifier: String?
    public var includesNotes: Bool
    public var includesTags: Bool
    /// How session times are written to events. Work logs always keep exact times.
    public var eventTiming: CalendarEventTiming

    public init(
        isSyncEnabled: Bool = true,
        defaultCalendarIdentifier: String? = nil,
        includesNotes: Bool = true,
        includesTags: Bool = true,
        eventTiming: CalendarEventTiming = .default
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.defaultCalendarIdentifier = defaultCalendarIdentifier
        self.includesNotes = includesNotes
        self.includesTags = includesTags
        self.eventTiming = eventTiming
    }
}

/// Synchronization state of a completed session's Calendar event.
public enum CalendarSyncStatus: String, Codable, CaseIterable, Sendable {
    /// No event exists and none has been attempted (or sync is turned off).
    case notSynced
    /// An app-owned event exists and reflects the session.
    case synced
    /// The last attempt failed; the session itself is safe.
    case failed
    /// The app-owned event was removed outside the app.
    case eventMissing

    public var displayName: String {
        switch self {
        case .notSynced: "Not in Calendar"
        case .synced: "In Calendar"
        case .failed: "Sync Failed"
        case .eventMissing: "Event Missing"
        }
    }

    public var needsAttention: Bool { self == .failed || self == .eventMissing }
}
