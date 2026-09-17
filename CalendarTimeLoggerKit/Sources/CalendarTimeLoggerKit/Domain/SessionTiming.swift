import Foundation

/// A single pause inside a session. `end` is `nil` while the pause is ongoing.
public struct PauseInterval: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date?

    public init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

/// Timestamp-based duration math for a session.
///
/// Durations are always derived from timestamps, never from a counter, so they
/// stay correct across sleep, suspension, relaunch, and UI refresh delays.
public struct SessionTiming: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var pauses: [PauseInterval]

    public init(startedAt: Date, endedAt: Date? = nil, pauses: [PauseInterval] = []) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pauses = pauses
    }

    private func upperBound(at now: Date) -> Date {
        max(startedAt, endedAt ?? now)
    }

    /// Time between start and finish (or `now` for an open session).
    public func wallClockDuration(at now: Date) -> TimeInterval {
        Self.rounded(upperBound(at: now).timeIntervalSince(startedAt))
    }

    /// `Date` arithmetic accumulates floating-point error (7139.9999… instead
    /// of 7140). Rounding to milliseconds keeps floor-based formatting exact.
    static func rounded(_ interval: TimeInterval) -> TimeInterval {
        (interval * 1000).rounded() / 1000
    }

    /// Total paused time, clipped to the session interval.
    public func pausedDuration(at now: Date) -> TimeInterval {
        let upper = upperBound(at: now)
        let total = pauses.reduce(0.0) { sum, pause in
            let start = max(pause.start, startedAt)
            let end = min(pause.end ?? upper, upper)
            return sum + max(0, end.timeIntervalSince(start))
        }
        return min(Self.rounded(total), wallClockDuration(at: now))
    }

    /// Wall-clock time minus paused time.
    public func activeDuration(at now: Date) -> TimeInterval {
        Self.rounded(max(0, wallClockDuration(at: now) - pausedDuration(at: now)))
    }

    /// Whether the session currently has an open pause.
    public var hasOpenPause: Bool { pauses.last.map { $0.end == nil } ?? false }

    /// Returns pauses clipped to `[startedAt, endedAt]`, dropping empty ones and
    /// closing any open pause at the end. Used when the user edits session times.
    public func normalizedPauses() -> [PauseInterval] {
        guard let endedAt else { return pauses }
        return pauses.compactMap { pause in
            let start = max(pause.start, startedAt)
            let end = min(pause.end ?? endedAt, endedAt)
            guard end > start else { return nil }
            return PauseInterval(start: start, end: end)
        }
    }
}
