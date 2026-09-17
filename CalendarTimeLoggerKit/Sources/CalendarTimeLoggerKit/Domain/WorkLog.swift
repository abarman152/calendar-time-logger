import Foundation

/// A read-only projection of a work session used by Work Logs, analytics,
/// notifications, and Calendar notes.
///
/// Work Logs are not stored separately: they are derived from `WorkSession`
/// so recorded work has exactly one source of truth (ADR-004).
public struct WorkLog: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let templateID: UUID?
    public let templateName: String
    /// SF Symbol name; legacy emoji snapshots are resolved to a symbol.
    public let templateIcon: String
    public let templateColor: HexColor
    public let state: SessionState
    public let startedAt: Date
    /// Finish time, or the evaluation time for an in-progress session.
    public let endedAt: Date
    public let wallClockDuration: TimeInterval
    public let pausedDuration: TimeInterval
    public let activeDuration: TimeInterval
    public let pauseCount: Int
    public let notes: String
    public let tags: [String]
    /// The classification recorded on the session itself.
    public let taskPriority: TaskPriority
    /// The category recorded on the session itself.
    public let category: String
    public let calendarSyncStatus: CalendarSyncStatus
    public let calendarSyncMessage: String?
    public let hasCalendarEvent: Bool

    public var isInProgress: Bool { state.isOpen }
    public var isUrgent: Bool { taskPriority.isUrgent }
    public var isImportant: Bool { taskPriority.isImportant }

    public init(
        id: UUID = UUID(),
        templateID: UUID?,
        templateName: String,
        templateIcon: String,
        templateColor: HexColor,
        state: SessionState = .completed,
        timing: SessionTiming,
        now: Date,
        notes: String = "",
        tags: [String] = [],
        taskPriority: TaskPriority = .default,
        category: String = WorkCategory.defaultName,
        calendarSyncStatus: CalendarSyncStatus = .notSynced,
        calendarSyncMessage: String? = nil,
        hasCalendarEvent: Bool = false
    ) {
        self.id = id
        self.templateID = templateID
        self.templateName = templateName
        self.templateIcon = TemplateSymbol.displayName(templateIcon)
        self.templateColor = templateColor
        self.state = state
        self.startedAt = timing.startedAt
        self.endedAt = max(timing.startedAt, timing.endedAt ?? now)
        self.wallClockDuration = timing.wallClockDuration(at: now)
        self.pausedDuration = timing.pausedDuration(at: now)
        self.activeDuration = timing.activeDuration(at: now)
        self.pauseCount = timing.pauses.count
        self.notes = notes
        self.tags = tags
        self.taskPriority = taskPriority
        self.category = WorkCategory.stored(category)
        self.calendarSyncStatus = calendarSyncStatus
        self.calendarSyncMessage = calendarSyncMessage
        self.hasCalendarEvent = hasCalendarEvent
    }

    /// Builds a log from a session. `now` is used for open sessions.
    public init(session: WorkSession, now: Date = Date()) {
        self.init(
            id: session.id,
            templateID: session.templateID,
            templateName: session.templateName,
            templateIcon: session.templateIcon,
            templateColor: session.templateColor,
            state: session.state,
            timing: session.timing,
            now: now,
            notes: session.notes,
            tags: session.tags,
            taskPriority: session.taskPriority,
            category: session.category,
            calendarSyncStatus: session.calendarSyncStatus,
            calendarSyncMessage: session.calendarSyncMessage,
            hasCalendarEvent: session.calendarEventIdentifier != nil
        )
    }
}

public struct WorkLogDayGroup: Identifiable, Hashable, Sendable {
    public let day: Date
    public let logs: [WorkLog]
    public var id: Date { day }
    public var totalActiveDuration: TimeInterval { logs.reduce(0) { $0 + $1.activeDuration } }
}

public struct WorkLogFilter: Hashable, Sendable {
    public var searchText: String
    public var templateID: UUID?
    public var tag: String?
    public var syncStatus: CalendarSyncStatus?
    /// `nil` includes every classification.
    public var priority: TaskPriorityFilter?
    /// A category name, matched case-insensitively. `nil` includes every category.
    public var category: String?
    public var dateInterval: DateInterval?

    public init(
        searchText: String = "",
        templateID: UUID? = nil,
        tag: String? = nil,
        syncStatus: CalendarSyncStatus? = nil,
        priority: TaskPriorityFilter? = nil,
        category: String? = nil,
        dateInterval: DateInterval? = nil
    ) {
        self.searchText = searchText
        self.templateID = templateID
        self.tag = tag
        self.syncStatus = syncStatus
        self.priority = priority
        self.category = category
        self.dateInterval = dateInterval
    }

    public var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || templateID != nil || tag != nil
            || syncStatus != nil || priority != nil || category != nil || dateInterval != nil
    }
}

public enum WorkLogQuery {
    /// Applies a filter. Search matches template name, category, notes, and tags.
    public static func filter(_ logs: [WorkLog], with filter: WorkLogFilter) -> [WorkLog] {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagQuery = query.hasPrefix("#") ? String(query.dropFirst()) : query
        return logs.filter { log in
            if let templateID = filter.templateID, log.templateID != templateID { return false }
            if let tag = filter.tag, !log.tags.contains(tag) { return false }
            if let status = filter.syncStatus, log.calendarSyncStatus != status { return false }
            if let priority = filter.priority, !priority.matches(log.taskPriority) { return false }
            if let category = filter.category, !WorkCategory.matches(log.category, category) { return false }
            if let interval = filter.dateInterval, !interval.contains(log.startedAt) { return false }
            guard !query.isEmpty else { return true }
            return log.templateName.localizedCaseInsensitiveContains(query)
                || log.category.localizedCaseInsensitiveContains(query)
                || log.notes.localizedCaseInsensitiveContains(query)
                || log.tags.contains { $0.localizedCaseInsensitiveContains(tagQuery) }
        }
    }

    /// Groups logs by the calendar day they started, newest day first, with
    /// logs inside a day ordered by start time.
    public static func groupByDay(_ logs: [WorkLog], calendar: Calendar = .current) -> [WorkLogDayGroup] {
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.startedAt) }
        return grouped
            .map { WorkLogDayGroup(day: $0.key, logs: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.day > $1.day }
    }

    /// All tags used across logs, sorted.
    public static func allTags(in logs: [WorkLog]) -> [String] {
        Array(Set(logs.flatMap(\.tags))).sorted()
    }

    /// Every category recorded in `logs`, one spelling per name, sorted.
    public static func allCategories(in logs: [WorkLog]) -> [String] {
        var byKey: [String: String] = [:]
        // The most recent spelling wins, matching how analytics names a group.
        for log in logs.sorted(by: { $0.startedAt < $1.startedAt }) {
            byKey[WorkCategory.key(log.category)] = log.category
        }
        return byKey.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
