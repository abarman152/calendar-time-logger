import Foundation

/// A span of recorded time, treated as the half-open interval `[start, end)`
/// (ADR-026).
///
/// The end instant belongs to whatever starts there, so a session that ends at
/// 11:00:00 and one that starts at 11:00:00 meet without overlapping. Nothing
/// here adds or removes time: the recorded timestamps are compared as they are.
public struct WorkInterval: Hashable, Sendable {
    public var start: Date
    public var end: Date

    /// An inverted pair is stored as an empty interval at `start`.
    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// `true` only when the two share some instant: `a.start < b.end && b.start < a.end`.
    /// Intervals that merely touch (`a.end == b.start`) don't overlap.
    public func overlaps(_ other: WorkInterval) -> Bool {
        start < other.end && other.start < end
    }

    /// `true` when one interval ends exactly where the other starts.
    public func isAdjacent(to other: WorkInterval) -> Bool {
        end == other.start || other.end == start
    }

    public func relation(to other: WorkInterval) -> Relation {
        if overlaps(other) {
            return .overlapping(min(end, other.end).timeIntervalSince(max(start, other.start)))
        }
        if isAdjacent(to: other) { return .adjacent }
        let gap = start >= other.end ? start.timeIntervalSince(other.end) : other.start.timeIntervalSince(end)
        return .separated(gap)
    }

    public enum Relation: Equatable, Sendable {
        /// Shared time, in seconds.
        case overlapping(TimeInterval)
        /// One ends exactly where the other starts.
        case adjacent
        /// Time between them, in seconds.
        case separated(TimeInterval)
    }
}

/// How Calendar Time Logger writes a finished session's start and finish times
/// to its Calendar event. The work log always keeps the exact times.
public enum CalendarEventTiming: String, CaseIterable, Identifiable, Sendable {
    /// The event uses the session's recorded start and finish, to the second.
    case exact
    /// The event's start and finish are each rounded to the nearest minute.
    ///
    /// Rounding both ends with the same rule never reverses order, so sessions
    /// that didn't overlap in Work Logs never overlap in Calendar, and sessions
    /// a few seconds apart meet on the same minute instead of sharing it.
    case nearestMinute

    public var id: String { rawValue }

    public static let `default` = CalendarEventTiming.exact

    public var title: String {
        switch self {
        case .exact: "Keep exact times"
        case .nearestMinute: "Round to the nearest minute"
        }
    }

    public var explanation: String {
        switch self {
        case .exact:
            "Events use each session’s exact start and finish times, to the second. Apple Calendar can draw a session that ends at 11:00:40 and one that starts at 11:00:52 side by side, because both fall in the 11:00 minute."
        case .nearestMinute:
            "Events start and finish on whole minutes, so back-to-back sessions stack cleanly in Apple Calendar. Only the Calendar event is rounded; Work Logs, Analytics, and exports keep the exact times."
        }
    }

    /// The start and end to write to Calendar for a session recorded over `interval`.
    public func eventInterval(for interval: WorkInterval, calendar: Calendar = .current) -> WorkInterval {
        switch self {
        case .exact:
            return interval
        case .nearestMinute:
            let start = Self.nearestMinute(interval.start, calendar: calendar)
            let end = Self.nearestMinute(interval.end, calendar: calendar)
            // A session shorter than half a minute would round to nothing; keep
            // its exact times rather than invent a length.
            guard end > start else { return interval }
            return WorkInterval(start: start, end: end)
        }
    }

    /// Rounds half a minute and more up, anything less down.
    static func nearestMinute(_ date: Date, calendar: Calendar) -> Date {
        guard let minute = calendar.dateInterval(of: .minute, for: date)?.start else { return date }
        return date.timeIntervalSince(minute) >= 30 ? minute.addingTimeInterval(60) : minute
    }
}

/// Minute-precision time editing.
public enum MinuteEditing {
    /// The value to store when a picker that shows hours and minutes changes a time.
    ///
    /// A macOS date picker without seconds still carries the original seconds,
    /// so choosing 11:00 for a time recorded at 11:02:15 would store 11:00:15 —
    /// a hidden overlap with a session that ended at 11:00:00. When the picked
    /// minute differs from the original, the seconds are cleared; an untouched
    /// time keeps its exact recorded value.
    public static func pickedTime(original: Date, picked: Date, calendar: Calendar = .current) -> Date {
        let originalMinute = calendar.dateInterval(of: .minute, for: original)?.start ?? original
        let pickedMinute = calendar.dateInterval(of: .minute, for: picked)?.start ?? picked
        return pickedMinute == originalMinute ? original : pickedMinute
    }
}
