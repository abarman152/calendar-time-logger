import Foundation
import SwiftData

/// Version 1 of the persisted schema, as shipped in 1.0 and 1.1.
///
/// The models below are a **frozen copy** of the 1.1 shape. They are never
/// edited and never used to record work; they exist so a migration has a source
/// to map from. A `SchemaMigrationPlan` identifies the version a store was
/// written with by matching the store's entity hashes against each
/// `VersionedSchema`, so every past version needs its own model definitions —
/// pointing an older version at the current models makes both versions hash
/// identically and the migration fails ([ADR-022](Documentation/Decisions/ADR-022-task-priority-model.md)).
///
/// Entity names come from the type names, so these must keep the names
/// `WorkTemplate` and `WorkSession`.
public enum CalendarTimeLoggerSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
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
