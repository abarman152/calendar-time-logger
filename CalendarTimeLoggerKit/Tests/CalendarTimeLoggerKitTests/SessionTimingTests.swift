import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@Suite("Duration calculation")
struct SessionTimingTests {
    let start = TestDates.date(2026, 9, 15, 10, 0)

    func at(_ hour: Int, _ minute: Int) -> Date { TestDates.date(2026, 9, 15, hour, minute) }

    @Test("Documented example: 10:00–12:24 with a 25 minute pause")
    func documentedExample() {
        let timing = SessionTiming(startedAt: start, endedAt: at(12, 24),
                                   pauses: [PauseInterval(start: at(11, 15), end: at(11, 40))])
        #expect(timing.wallClockDuration(at: .distantFuture) == 2 * 3600 + 24 * 60)
        #expect(timing.pausedDuration(at: .distantFuture) == 25 * 60)
        #expect(timing.activeDuration(at: .distantFuture) == 3600 + 59 * 60)
    }

    @Test("Open session uses now; open pause counts until now")
    func openSession() {
        let timing = SessionTiming(startedAt: start, pauses: [PauseInterval(start: at(10, 30))])
        let now = at(10, 45)
        #expect(timing.wallClockDuration(at: now) == 45 * 60)
        #expect(timing.pausedDuration(at: now) == 15 * 60)
        #expect(timing.activeDuration(at: now) == 30 * 60)
        #expect(timing.hasOpenPause)
    }

    @Test("Clock moving backwards never produces negative durations")
    func clockSkew() {
        let timing = SessionTiming(startedAt: start)
        let past = start.addingTimeInterval(-600)
        #expect(timing.wallClockDuration(at: past) == 0)
        #expect(timing.activeDuration(at: past) == 0)
    }

    @Test("Pauses outside the session are clipped")
    func pausesClipped() {
        let timing = SessionTiming(startedAt: start, endedAt: at(11, 0), pauses: [
            PauseInterval(start: at(9, 50), end: at(10, 10)),
            PauseInterval(start: at(10, 55), end: at(11, 20))
        ])
        #expect(timing.pausedDuration(at: .distantFuture) == 15 * 60)
        #expect(timing.activeDuration(at: .distantFuture) == 45 * 60)
        let normalized = timing.normalizedPauses()
        #expect(normalized == [PauseInterval(start: start, end: at(10, 10)), PauseInterval(start: at(10, 55), end: at(11, 0))])
    }

    @Test("Duration formatting")
    func formatting() {
        #expect(DurationFormatting.clock(2 * 3600 + 24 * 60 + 18) == "02:24:18")
        #expect(DurationFormatting.clock(2 * 3600 + 24 * 60 + 18, showsSeconds: false) == "02:24")
        #expect(DurationFormatting.short(2 * 3600 + 24 * 60) == "2h 24m")
        #expect(DurationFormatting.short(48 * 60 + 59) == "48m")
        #expect(DurationFormatting.short(3 * 3600) == "3h")
        #expect(DurationFormatting.short(30) == "< 1m")
        #expect(DurationFormatting.spoken(3600 + 60) == "1 hour, 1 minute")
        #expect(DurationFormatting.spoken(5, includesSeconds: true) == "5 seconds")
    }
}
