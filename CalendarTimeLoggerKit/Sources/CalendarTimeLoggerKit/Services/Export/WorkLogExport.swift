import Foundation

/// Which work logs an export includes.
public enum WorkLogExportScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case currentFilter
    case today
    case thisWeek
    case thisMonth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All Work Logs"
        case .currentFilter: "Current Filter"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        }
    }

    /// The date range for date-based scopes; `nil` for All and Current Filter.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all, .currentFilter: nil
        case .today: calendar.dateInterval(of: .day, for: now)
        case .thisWeek: calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth: calendar.dateInterval(of: .month, for: now)
        }
    }

    /// Scopes offered in the export sheet. Current Filter only appears when a
    /// filter is active.
    public static func available(filterIsActive: Bool) -> [WorkLogExportScope] {
        allCases.filter { $0 != .currentFilter || filterIsActive }
    }
}

/// One exported session: the user-facing fields of a completed work log.
/// Internal database identifiers are deliberately not included.
public struct WorkLogExportRecord: Hashable, Sendable {
    public let log: WorkLog
    public let calendarName: String
    public let calendarEventIdentifier: String

    public init(log: WorkLog, calendarName: String, calendarEventIdentifier: String) {
        self.log = log
        self.calendarName = calendarName
        self.calendarEventIdentifier = calendarEventIdentifier
    }
}

/// Builds the export workbook: a Work Logs sheet with one row per session and
/// an optional Summary sheet with totals by template, category, task priority, day, and week.
public enum WorkLogWorkbookBuilder {
    public static func workbook(
        records: [WorkLogExportRecord],
        columns: WorkLogColumnSelection = .default,
        scopeTitle: String,
        generatedAt: Date,
        includesSummary: Bool,
        calendar: Calendar = .current
    ) -> SpreadsheetWorkbook {
        let sorted = records.sorted { $0.log.startedAt < $1.log.startedAt }
        var sheets = [logSheet(sorted, columns: columns, calendar: calendar)]
        if includesSummary {
            sheets.append(summarySheet(sorted, scopeTitle: scopeTitle, generatedAt: generatedAt, calendar: calendar))
        }
        return SpreadsheetWorkbook(sheets: sheets)
    }

    /// One row per session, with exactly the chosen columns in the chosen order.
    static func logSheet(_ records: [WorkLogExportRecord], columns: WorkLogColumnSelection, calendar: Calendar) -> SpreadsheetSheet {
        let selected = columns.columns
        var rows: [[SpreadsheetCell]] = [selected.map { .text($0.title, .header) }]
        for record in records {
            rows.append(selected.map { $0.cell(for: record, calendar: calendar) })
        }
        return SpreadsheetSheet(name: "Work Logs", columnWidths: selected.map(\.width), rows: rows, hasHeaderRow: true)
    }

    static func summarySheet(_ records: [WorkLogExportRecord], scopeTitle: String, generatedAt: Date, calendar: Calendar) -> SpreadsheetSheet {
        let logs = records.map(\.log)
        var rows: [[SpreadsheetCell]] = []
        rows.append([.text("Work Log Summary", .title)])
        rows.append([.text("Scope", .bold), .text(scopeTitle)])
        rows.append([.text("Exported", .bold), .date(generatedAt, .dateTime)])
        rows.append([.text("Sessions", .bold), .number(Double(logs.count), .integer)])
        rows.append([])

        rows.append([.text("Totals", .header), .text("", .header)])
        rows.append([.text("Total Work"), .duration(logs.reduce(0) { $0 + $1.wallClockDuration })])
        rows.append([.text("Total Active Work"), .duration(logs.reduce(0) { $0 + $1.activeDuration })])
        rows.append([.text("Total Paused Time"), .duration(logs.reduce(0) { $0 + $1.pausedDuration })])
        rows.append([])

        let totalActive = WorkAnalytics.totalActiveDuration(logs)
        rows.append([.text("Work by Template", .header), .text("Sessions", .header), .text("Active Work", .header), .text("Share", .header)])
        for total in WorkAnalytics.templateTotals(logs) {
            rows.append([
                .text(total.name),
                .number(Double(total.sessionCount), .integer),
                .duration(total.duration),
                .number(totalActive > 0 ? total.duration / totalActive : 0, .percent)
            ])
        }
        rows.append([])

        rows.append([.text("Work by Category", .header), .text("Sessions", .header), .text("Active Work", .header), .text("Share", .header)])
        for total in WorkAnalytics.categoryTotals(logs) {
            rows.append([
                .text(total.name),
                .number(Double(total.sessionCount), .integer),
                .duration(total.duration),
                .number(total.share, .percent)
            ])
        }
        rows.append([])

        rows.append([.text("Work by Task Priority", .header), .text("Sessions", .header), .text("Active Work", .header), .text("Share", .header)])
        for total in WorkAnalytics.priorityTotals(logs) {
            rows.append([
                .text(total.quadrant.title),
                .number(Double(total.sessionCount), .integer),
                .duration(total.duration),
                .number(total.share, .percent)
            ])
        }
        rows.append([.text("Urgent (any)"), .number(Double(logs.filter(\.isUrgent).count), .integer),
                     .duration(WorkAnalytics.urgentDuration(logs)),
                     .number(totalActive > 0 ? WorkAnalytics.urgentDuration(logs) / totalActive : 0, .percent)])
        rows.append([.text("Important (any)"), .number(Double(logs.filter(\.isImportant).count), .integer),
                     .duration(WorkAnalytics.importantDuration(logs)),
                     .number(totalActive > 0 ? WorkAnalytics.importantDuration(logs) / totalActive : 0, .percent)])
        rows.append([])

        rows.append([.text("Daily Totals", .header), .text("Sessions", .header), .text("Total Work", .header), .text("Active Work", .header)])
        for group in periodTotals(logs, component: .day, calendar: calendar) {
            rows.append([.date(group.start, .date), .number(Double(group.count), .integer), .duration(group.wallClock), .duration(group.active)])
        }
        rows.append([])

        rows.append([.text("Weekly Totals (week starting)", .header), .text("Sessions", .header), .text("Total Work", .header), .text("Active Work", .header)])
        for group in periodTotals(logs, component: .weekOfYear, calendar: calendar) {
            rows.append([.date(group.start, .date), .number(Double(group.count), .integer), .duration(group.wallClock), .duration(group.active)])
        }

        // Column B holds the export date and time, so it's wide enough for them.
        return SpreadsheetSheet(name: "Summary", columnWidths: [30, 22, 14, 14], rows: rows)
    }

    struct PeriodTotal: Equatable {
        let start: Date
        let count: Int
        let wallClock: TimeInterval
        let active: TimeInterval
    }

    /// Totals per day or week, oldest first. Sessions count toward the period
    /// they started in, like the rest of the app.
    static func periodTotals(_ logs: [WorkLog], component: Calendar.Component, calendar: Calendar) -> [PeriodTotal] {
        let grouped = Dictionary(grouping: logs) { calendar.dateInterval(of: component, for: $0.startedAt)?.start ?? calendar.startOfDay(for: $0.startedAt) }
        return grouped.map { start, logs in
            PeriodTotal(start: start, count: logs.count,
                        wallClock: logs.reduce(0) { $0 + $1.wallClockDuration },
                        active: logs.reduce(0) { $0 + $1.activeDuration })
        }
        .sorted { $0.start < $1.start }
    }
}
