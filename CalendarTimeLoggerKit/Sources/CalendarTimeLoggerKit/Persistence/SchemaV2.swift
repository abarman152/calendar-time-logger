import Foundation
import SwiftData

/// Version 2 of the persisted schema, as shipped in 1.2: version 1 plus task
/// priority (`isUrgent`, `isImportant`) on templates and sessions (ADR-022).
///
/// Like `CalendarTimeLoggerSchemaV1`, the models below are a **frozen copy** of
/// the 1.2 shape. They are never edited and never used to record work; they
/// let the migration plan recognize a 1.2 store by its entity hashes. Entity
/// names come from the type names, so these must keep the names
/// `WorkTemplate` and `WorkSession`.
public enum CalendarTimeLoggerSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    // The nested types below, not the current models.
    public static var models: [any PersistentModel.Type] { [WorkTemplate.self, WorkSession.self] }

    @Model
    public final class WorkTemplate {
        public var id: UUID = UUID()
        public var name: String = ""
        public var icon: String = TemplateSymbol.defaultName
        public var colorHex: String = "#0A84FF"
        public var calendarIdentifier: String?
        public var tags: [String] = []
        public var notes: String = ""
        public var isUrgent: Bool = false
        public var isImportant: Bool = false
        public var sortOrder: Int = 0
        public var createdAt: Date = Date()
        public var modifiedAt: Date = Date()
        var menuBarConfigurationData: Data?
        var notificationBehaviorData: Data?

        public init() {}
    }

    @Model
    public final class WorkSession {
        public var id: UUID = UUID()
        public var templateID: UUID?
        public var templateName: String = ""
        public var templateIcon: String = ""
        public var templateColorHex: String = "#0A84FF"
        public var stateRawValue: String = SessionState.active.rawValue
        public var startedAt: Date = Date()
        public var endedAt: Date?
        var pauseIntervalsData: Data?
        public var notes: String = ""
        public var tags: [String] = []
        public var isUrgent: Bool = false
        public var isImportant: Bool = false
        public var calendarIdentifier: String?
        public var calendarEventIdentifier: String?
        public var eventCalendarIdentifier: String?
        public var calendarSyncStatusRawValue: String = CalendarSyncStatus.notSynced.rawValue
        public var calendarSyncMessage: String?
        public var calendarLastSyncedAt: Date?
        public var lastHeartbeatAt: Date?
        public var createdAt: Date = Date()
        public var modifiedAt: Date = Date()

        public init() {}
    }
}
