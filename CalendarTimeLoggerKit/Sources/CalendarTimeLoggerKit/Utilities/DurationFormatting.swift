import Foundation

/// Deterministic duration formatting used by the UI, menu bar, notifications,
/// and Calendar event notes.
public enum DurationFormatting {
    /// `02:24:18`, or `02:24` when `showsSeconds` is false.
    public static func clock(_ interval: TimeInterval, showsSeconds: Bool = true) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if showsSeconds {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// `2h 24m`, `48m`, `3h`, or `< 1m`.
    public static func short(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval.rounded(.down))) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, 0): return "< 1m"
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }

    /// `2 hours, 24 minutes` — used for VoiceOver.
    public static func spoken(_ interval: TimeInterval, includesSeconds: Bool = false) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if includesSeconds, seconds > 0 || parts.isEmpty {
            parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")
        }
        if parts.isEmpty { return "less than a minute" }
        return parts.joined(separator: ", ")
    }
}
