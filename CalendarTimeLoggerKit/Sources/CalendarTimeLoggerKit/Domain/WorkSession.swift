import Foundation
import SwiftData

/// A live or finished work session. This is the source of truth for recorded
/// work; the Apple Calendar event is derived from it.
@Model
public final class WorkSession {
    public var id: UUID = UUID()
    /// The template the session was started from. Not a relationship, so a
    /// deleted template never removes recorded work.
    public var templateID: UUID?
    // Snapshots of the template identity at start time, so Work Logs stay
    // readable if the template is renamed or deleted later.
    public var templateName: String = ""
    /// SF Symbol name at start time (1.0 stored an emoji; see `IconMigration`).
    public var templateIcon: String = ""
    public var templateColorHex: String = "#0A84FF"

    /// Raw storage for `state`; readable for `#Predicate` queries.
    public internal(set) var stateRawValue: String = SessionState.active.rawValue
    public var startedAt: Date = Date()
    /// Finish time for completed sessions, cancel time for cancelled ones.
    public var endedAt: Date?
    var pauseIntervalsData: Data?

    public var notes: String = ""
    public var tags: [String] = []

    /// The task classification captured when this session started. It is the
    /// session's own value: editing the template later never changes it
    /// (ADR-022). Sessions recorded before 1.2 read as `false`/`false`.
    public var isUrgent: Bool = false
    public var isImportant: Bool = false

    /// The category captured when this session started (from its template, or
    /// chosen for this session). Like task priority it belongs to the session:
    /// changing the template's category later never changes it (ADR-025).
    /// Sessions recorded before 1.3 read as `WorkCategory.defaultName`.
    public var category: String = WorkCategory.defaultName

    /// Explicit per-session calendar choice. `nil` falls back to the template,
    /// then the global default.
    public var calendarIdentifier: String?

    // External Calendar references. These are never used as identity.
    public var calendarEventIdentifier: String?
    public var eventCalendarIdentifier: String?
    public internal(set) var calendarSyncStatusRawValue: String = CalendarSyncStatus.notSynced.rawValue
    public var calendarSyncMessage: String?
    public var calendarLastSyncedAt: Date?

    /// Last time the running app confirmed this open session. Used by crash
    /// recovery to offer finishing at the last known time.
    public var lastHeartbeatAt: Date?

    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        templateID: UUID?,
        templateName: String,
        templateIcon: String,
        templateColorHex: String,
        startedAt: Date,
        tags: [String] = [],
        notes: String = "",
        taskPriority: TaskPriority = .default,
        category: String = WorkCategory.defaultName
    ) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.templateIcon = templateIcon
        self.templateColorHex = templateColorHex
        self.startedAt = startedAt
        self.tags = tags
        self.notes = notes
        self.isUrgent = taskPriority.isUrgent
        self.isImportant = taskPriority.isImportant
        self.category = WorkCategory.stored(category)
        self.stateRawValue = SessionState.active.rawValue
        self.createdAt = startedAt
        self.modifiedAt = startedAt
    }

    public var state: SessionState {
        get { SessionState(rawValue: stateRawValue) ?? .active }
        set { stateRawValue = newValue.rawValue }
    }

    /// The classification recorded for this session.
    public var taskPriority: TaskPriority {
        get { TaskPriority(isUrgent: isUrgent, isImportant: isImportant) }
        set {
            isUrgent = newValue.isUrgent
            isImportant = newValue.isImportant
        }
    }

    public var pauses: [PauseInterval] {
        get { JSONCoding.decode([PauseInterval].self, from: pauseIntervalsData) ?? [] }
        set { pauseIntervalsData = JSONCoding.encode(newValue) }
    }

    public var calendarSyncStatus: CalendarSyncStatus {
        get { CalendarSyncStatus(rawValue: calendarSyncStatusRawValue) ?? .notSynced }
        set { calendarSyncStatusRawValue = newValue.rawValue }
    }

    public var timing: SessionTiming {
        SessionTiming(startedAt: startedAt, endedAt: endedAt, pauses: pauses)
    }

    /// The template symbol to draw. Always a catalog symbol.
    public var templateSymbolName: String { TemplateSymbol.displayName(templateIcon) }

    public var templateColor: HexColor {
        HexColor(hex: templateColorHex) ?? TemplatePalette.colors[0].color
    }

    public func wallClockDuration(at now: Date) -> TimeInterval { timing.wallClockDuration(at: now) }
    public func pausedDuration(at now: Date) -> TimeInterval { timing.pausedDuration(at: now) }
    public func activeDuration(at now: Date) -> TimeInterval { timing.activeDuration(at: now) }

    /// The most recent time the session was resumed or started.
    public var lastResumedAt: Date {
        pauses.last?.end ?? startedAt
    }

    /// The URL stored on app-owned Calendar events. It identifies the event as
    /// belonging to this session without exposing details in the event notes.
    public var calendarOwnershipURL: URL {
        CalendarOwnership.url(for: id)
    }
}

public enum CalendarOwnership {
    public static let scheme = "calendartimelogger"

    public static func url(for sessionID: UUID) -> URL {
        URL(string: "\(scheme)://session/\(sessionID.uuidString)")!
    }

    /// Returns the session identifier encoded in an app-owned event URL.
    public static func sessionID(from url: URL?) -> UUID? {
        guard let url, url.scheme == scheme, url.host() == "session" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
