import Foundation

/// Active-work total for one template.
public struct TemplateTotal: Identifiable, Hashable, Sendable {
    /// Grouping key: the template ID, or the snapshot name for logs whose
    /// template no longer exists.
    public let key: String
    public let templateID: UUID?
    public let name: String
    public let icon: String
    public let color: HexColor
    public let duration: TimeInterval
    public let sessionCount: Int
    public var id: String { key }
}

/// Active-work total for one of the four task-priority combinations.
public struct PriorityTotal: Identifiable, Hashable, Sendable {
    public let quadrant: TaskPriorityQuadrant
    public let duration: TimeInterval
    public let sessionCount: Int
    /// Share of the active work in the same set of logs, 0–1. `0` when there
    /// is no work, so an empty range never shows a misleading percentage.
    public let share: Double
    public var id: String { quadrant.rawValue }
}

/// Active-work totals for one template, split by task priority.
public struct TemplatePriorityTotal: Identifiable, Hashable, Sendable {
    public let template: TemplateTotal
    /// Time on sessions marked urgent (important or not).
    public let urgentDuration: TimeInterval
    /// Time on sessions marked important (urgent or not).
    public let importantDuration: TimeInterval
    public let quadrants: [PriorityTotal]
    public var id: String { template.key }
}

/// Active-work totals for one category, with the templates and priority
/// combinations inside it.
public struct CategoryTotal: Identifiable, Hashable, Sendable {
    /// Case-insensitive grouping key (see `WorkCategory.key`).
    public let key: String
    /// The most recently recorded spelling.
    public let name: String
    public let duration: TimeInterval
    public let sessionCount: Int
    /// Share of the active work in the same set of logs, 0–1; `0` when there is no work.
    public let share: Double
    /// Templates (and quick tasks) recorded in this category, longest first.
    public let templates: [TemplateTotal]
    /// All four priority combinations within this category, always in display order.
    public let quadrants: [PriorityTotal]
    public var id: String { key }
}

/// Headline numbers for a date range.
public struct WorkSummary: Hashable, Sendable {
    public let totalActiveDuration: TimeInterval
    public let sessionCount: Int
    /// Mean active duration per session; `0` when there are no sessions.
    public let averageSessionDuration: TimeInterval
    public let urgentDuration: TimeInterval
    public let importantDuration: TimeInterval
    public let urgentAndImportantDuration: TimeInterval
    public let neitherDuration: TimeInterval
}

/// Active-work totals for one day.
public struct DailyTotal: Identifiable, Hashable, Sendable {
    public let day: Date
    public let templates: [TemplateTotal]
    public var id: Date { day }
    public var total: TimeInterval { templates.reduce(0) { $0 + $1.duration } }
}

/// Aggregations used by the Dashboard and Analytics screens.
///
/// All totals use active duration (paused time excluded) and attribute a
/// session to the day it started.
public enum WorkAnalytics {
    public static func totalActiveDuration(_ logs: [WorkLog]) -> TimeInterval {
        logs.reduce(0) { $0 + $1.activeDuration }
    }

    public static func logs(_ logs: [WorkLog], in interval: DateInterval) -> [WorkLog] {
        logs.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
    }

    /// Per-template totals, longest first.
    public static func templateTotals(_ logs: [WorkLog]) -> [TemplateTotal] {
        let grouped = Dictionary(grouping: logs) { log in
            log.templateID?.uuidString ?? "name:\(log.templateName)"
        }
        return grouped.map { key, logs in
            // Use the most recent snapshot so renamed templates show current identity.
            let latest = logs.max { $0.startedAt < $1.startedAt }!
            return TemplateTotal(
                key: key,
                templateID: latest.templateID,
                name: latest.templateName,
                icon: latest.templateIcon,
                color: latest.templateColor,
                duration: totalActiveDuration(logs),
                sessionCount: logs.count
            )
        }
        .sorted { lhs, rhs in
            lhs.duration == rhs.duration ? lhs.name < rhs.name : lhs.duration > rhs.duration
        }
    }

    // MARK: Task priority

    /// Totals for all four combinations, always in the same order and always
    /// complete, so the quadrant view keeps its shape when a combination is
    /// unused.
    public static func priorityTotals(_ logs: [WorkLog]) -> [PriorityTotal] {
        let total = totalActiveDuration(logs)
        let grouped = Dictionary(grouping: logs) { $0.taskPriority.quadrant }
        return TaskPriorityQuadrant.displayOrder.map { quadrant in
            let matching = grouped[quadrant] ?? []
            let duration = totalActiveDuration(matching)
            return PriorityTotal(
                quadrant: quadrant,
                duration: duration,
                sessionCount: matching.count,
                share: total > 0 ? duration / total : 0
            )
        }
    }

    /// Active work on sessions marked urgent (important or not).
    public static func urgentDuration(_ logs: [WorkLog]) -> TimeInterval {
        totalActiveDuration(logs.filter(\.isUrgent))
    }

    /// Active work on sessions marked important (urgent or not).
    public static func importantDuration(_ logs: [WorkLog]) -> TimeInterval {
        totalActiveDuration(logs.filter(\.isImportant))
    }

    public static func summary(_ logs: [WorkLog]) -> WorkSummary {
        let total = totalActiveDuration(logs)
        return WorkSummary(
            totalActiveDuration: total,
            sessionCount: logs.count,
            averageSessionDuration: logs.isEmpty ? 0 : total / Double(logs.count),
            urgentDuration: urgentDuration(logs),
            importantDuration: importantDuration(logs),
            urgentAndImportantDuration: totalActiveDuration(logs.filter { $0.isUrgent && $0.isImportant }),
            neitherDuration: totalActiveDuration(logs.filter { !$0.isUrgent && !$0.isImportant })
        )
    }

    /// Per-template totals split by priority, longest first. Only templates
    /// with recorded work appear.
    public static func templatePriorityTotals(_ logs: [WorkLog]) -> [TemplatePriorityTotal] {
        let byKey = Dictionary(grouping: logs) { log in log.templateID?.uuidString ?? "name:\(log.templateName)" }
        return templateTotals(logs).map { total in
            let matching = byKey[total.key] ?? []
            return TemplatePriorityTotal(
                template: total,
                urgentDuration: urgentDuration(matching),
                importantDuration: importantDuration(matching),
                quadrants: priorityTotals(matching)
            )
        }
    }

    // MARK: Categories

    /// Per-category totals, longest first, from one grouping pass over `logs`.
    ///
    /// Sessions are grouped by the category recorded on each session, never by
    /// a template's current category, so history is reported as it was
    /// recorded. Names that differ only by case are one category. Pass logs
    /// already limited to the selected date range.
    public static func categoryTotals(_ logs: [WorkLog]) -> [CategoryTotal] {
        let total = totalActiveDuration(logs)
        let grouped = Dictionary(grouping: logs) { WorkCategory.key($0.category) }
        return grouped.map { key, logs in
            let latest = logs.max { $0.startedAt < $1.startedAt }!
            let duration = totalActiveDuration(logs)
            return CategoryTotal(
                key: key,
                name: latest.category,
                duration: duration,
                sessionCount: logs.count,
                share: total > 0 ? duration / total : 0,
                templates: templateTotals(logs),
                quadrants: priorityTotals(logs)
            )
        }
        .sorted { lhs, rhs in
            lhs.duration == rhs.duration
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhs.duration > rhs.duration
        }
    }

    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }

    public static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)!
    }

    /// Totals for each of the `count` days ending on the day containing `date`.
    public static func dailyTotals(
        _ logs: [WorkLog],
        endingOn date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [DailyTotal] {
        let lastDay = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
            let interval = dayInterval(containing: day, calendar: calendar)
            return DailyTotal(day: day, templates: templateTotals(self.logs(logs, in: interval)))
        }
    }

    /// Consecutive days (ending today or yesterday) with at least one log.
    public static func currentStreak(_ logs: [WorkLog], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(logs.map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
