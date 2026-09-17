import Foundation

/// A column the user can include in an Excel export.
///
/// Every case maps to a value already shown in the app. Internal database
/// identifiers are deliberately not offered (ADR-018, ADR-023).
public enum WorkLogExportColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case date
    case startTime
    case endTime
    case duration
    case activeDuration
    case pausedDuration
    case template
    case category
    case urgent
    case important
    case taskPriority
    case tags
    case notes
    case calendar
    case calendarEventStatus
    case calendarEventIdentifier
    case sessionStatus

    public var id: String { rawValue }

    /// The header written into the workbook.
    public var title: String {
        switch self {
        case .date: "Date"
        case .startTime: "Start Time"
        case .endTime: "End Time"
        case .duration: "Duration"
        case .activeDuration: "Active Duration"
        case .pausedDuration: "Paused Duration"
        case .template: "Template"
        case .category: "Category"
        case .urgent: "Urgent"
        case .important: "Important"
        case .taskPriority: "Task Priority"
        case .tags: "Tags"
        case .notes: "Notes"
        case .calendar: "Calendar"
        case .calendarEventStatus: "Calendar Event Status"
        case .calendarEventIdentifier: "Calendar Event Identifier"
        case .sessionStatus: "Session Status"
        }
    }

    /// One line of explanation shown beside the checkbox in the export sheet.
    public var detail: String {
        switch self {
        case .date: "The day the session started"
        case .startTime: "Date and time the session started"
        case .endTime: "Date and time the session finished"
        case .duration: "Start to finish, including pauses"
        case .activeDuration: "Working time, excluding pauses"
        case .pausedDuration: "Total paused time"
        case .template: "Template name, or the quick task name"
        case .category: "The category recorded with the session"
        case .urgent: "Yes or No"
        case .important: "Yes or No"
        case .taskPriority: "The combination in words"
        case .tags: "Tags, separated by spaces"
        case .notes: "Session notes"
        case .calendar: "Calendar the event was created in"
        case .calendarEventStatus: "In Calendar, Not in Calendar, Sync Failed, or Event Missing"
        case .calendarEventIdentifier: "Apple Calendar's identifier for the event"
        case .sessionStatus: "Completed"
        }
    }

    /// Column width in characters.
    public var width: Double {
        switch self {
        case .date: 12
        case .startTime, .endTime: 20
        case .duration: 11
        case .activeDuration, .pausedDuration: 16
        case .template: 24
        case .category: 18
        case .urgent, .important: 10
        case .taskPriority: 24
        case .tags: 24
        case .notes: 48
        case .calendar: 18
        case .calendarEventStatus: 20
        case .calendarEventIdentifier: 38
        case .sessionStatus: 14
        }
    }

    /// Whether the column carries a date, duration, or text value. Used by the
    /// export preview, which shows readable text rather than Excel serials.
    public func cell(for record: WorkLogExportRecord, calendar: Calendar) -> SpreadsheetCell {
        let log = record.log
        switch self {
        case .date: return .date(calendar.startOfDay(for: log.startedAt), .date)
        case .startTime: return .date(log.startedAt, .dateTime)
        case .endTime: return .date(log.endedAt, .dateTime)
        case .duration: return .duration(log.wallClockDuration)
        case .activeDuration: return .duration(log.activeDuration)
        case .pausedDuration: return .duration(log.pausedDuration)
        case .template: return .text(log.templateName)
        case .category: return .text(log.category)
        case .urgent: return .text(TaskPriority.yesNo(log.isUrgent))
        case .important: return .text(TaskPriority.yesNo(log.isImportant))
        case .taskPriority: return .text(log.taskPriority.quadrant.title)
        case .tags: return .text(TagParsing.display(log.tags))
        case .notes: return .text(log.notes)
        case .calendar: return .text(record.calendarName)
        case .calendarEventStatus: return .text(log.calendarSyncStatus.displayName)
        case .calendarEventIdentifier: return .text(record.calendarEventIdentifier)
        case .sessionStatus: return .text(log.state.displayName)
        }
    }

    /// Readable text for the export preview, formatted the way the app shows
    /// the same value.
    public func previewText(for record: WorkLogExportRecord, calendar: Calendar) -> String {
        let log = record.log
        switch self {
        case .date: return log.startedAt.formatted(date: .numeric, time: .omitted)
        case .startTime, .endTime:
            let date = self == .startTime ? log.startedAt : log.endedAt
            return date.formatted(date: .omitted, time: .shortened)
        case .duration: return DurationFormatting.short(log.wallClockDuration)
        case .activeDuration: return DurationFormatting.short(log.activeDuration)
        case .pausedDuration: return log.pausedDuration < 60 ? "0m" : DurationFormatting.short(log.pausedDuration)
        default:
            if case .text(let value, _) = cell(for: record, calendar: calendar) {
                return value.replacingOccurrences(of: "\n", with: " ")
            }
            return ""
        }
    }
}

/// The columns an export includes, in the order the user arranged them.
///
/// The order is the workbook's column order, left to right.
public struct WorkLogColumnSelection: Hashable, Sendable {
    public private(set) var columns: [WorkLogExportColumn]

    /// Duplicates are removed; the first occurrence keeps its position.
    public init(_ columns: [WorkLogExportColumn]) {
        var seen = Set<WorkLogExportColumn>()
        self.columns = columns.filter { seen.insert($0).inserted }
    }

    /// What a new install exports: everything the Work Logs list shows, with
    /// category and priority beside the template.
    public static let `default` = WorkLogColumnSelection([
        .date, .startTime, .endTime, .duration, .activeDuration, .pausedDuration,
        .template, .category, .urgent, .important, .tags, .notes,
        .calendar, .calendarEventStatus, .calendarEventIdentifier, .sessionStatus
    ])

    public static let all = WorkLogColumnSelection(WorkLogExportColumn.allCases)

    public var isEmpty: Bool { columns.isEmpty }
    public var count: Int { columns.count }

    public func contains(_ column: WorkLogExportColumn) -> Bool { columns.contains(column) }

    /// Adds a column (at the end) or removes it.
    public mutating func toggle(_ column: WorkLogExportColumn) {
        if let index = columns.firstIndex(of: column) {
            columns.remove(at: index)
        } else {
            columns.append(column)
        }
    }

    /// Reorders columns, matching SwiftUI's `onMove` semantics (`destination`
    /// is an insertion point in the list before the move).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moved = source.sorted().compactMap { columns.indices.contains($0) ? columns[$0] : nil }
        guard !moved.isEmpty else { return }
        let insertion = destination - source.filter { $0 < destination }.count
        var remaining = columns
        for index in source.sorted(by: >) where remaining.indices.contains(index) {
            remaining.remove(at: index)
        }
        remaining.insert(contentsOf: moved, at: min(max(0, insertion), remaining.count))
        columns = remaining
    }

    public mutating func selectAll() { columns = WorkLogColumnSelection.all.columns }
    public mutating func deselectAll() { columns = [] }

    /// Stored in `UserDefaults` as raw values, so unknown names from a future
    /// version are ignored rather than breaking the setting.
    public var storageValue: String { columns.map(\.rawValue).joined(separator: ",") }

    public init?(storageValue: String) {
        let parsed = storageValue.split(separator: ",").compactMap { WorkLogExportColumn(rawValue: String($0)) }
        guard !parsed.isEmpty else { return nil }
        self.init(parsed)
    }
}

/// Ready-made column sets offered in the export sheet.
public enum WorkLogExportPreset: String, CaseIterable, Identifiable, Sendable {
    case basic
    case detailed
    case priorityAnalysis
    case categoryAnalysis
    case everything

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .basic: "Basic"
        case .detailed: "Detailed"
        case .priorityAnalysis: "Priority Analysis"
        case .categoryAnalysis: "Category Analysis"
        case .everything: "Everything"
        }
    }

    public var selection: WorkLogColumnSelection {
        switch self {
        case .basic:
            WorkLogColumnSelection([.date, .template, .activeDuration])
        case .detailed:
            WorkLogColumnSelection([.date, .startTime, .endTime, .duration, .activeDuration, .template,
                                    .category, .urgent, .important, .tags, .notes])
        case .priorityAnalysis:
            WorkLogColumnSelection([.date, .template, .activeDuration, .urgent, .important])
        case .categoryAnalysis:
            WorkLogColumnSelection([.date, .template, .category, .duration, .urgent, .important])
        case .everything:
            .all
        }
    }

    /// The preset matching a selection exactly, if any, so the sheet can show
    /// which one is in use.
    public static func matching(_ selection: WorkLogColumnSelection) -> WorkLogExportPreset? {
        allCases.first { $0.selection == selection }
    }
}
