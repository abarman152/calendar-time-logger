import Foundation
import Testing
@testable import CalendarTimeLoggerKit

/// Half-open interval semantics, Calendar event timing, and minute-precision
/// editing (ADR-026).
@MainActor
@Suite("Calendar event boundaries")
struct CalendarBoundaryTests {
    static let day = TestDates.date(2026, 9, 17)

    /// 10:00:30 style times on the test day.
    static func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second))
    }

    static func interval(_ start: (Int, Int, Int), _ end: (Int, Int, Int)) -> WorkInterval {
        WorkInterval(start: at(start.0, start.1, start.2), end: at(end.0, end.1, end.2))
    }

    // MARK: The regression matrix

    @Test("Boundary matrix: adjacent intervals never overlap; any shared second does", arguments: [
        // 1. 10:00–11:00 and 11:00–12:00
        ((10, 0, 0), (11, 0, 0), (11, 0, 0), (12, 0, 0), WorkInterval.Relation.adjacent),
        // 2. 10:00–11:00 and 10:59–12:00
        ((10, 0, 0), (11, 0, 0), (10, 59, 0), (12, 0, 0), .overlapping(60)),
        // 3. 10:00–12:00 and 11:00–12:00
        ((10, 0, 0), (12, 0, 0), (11, 0, 0), (12, 0, 0), .overlapping(3600)),
        // 4. 10:00–11:00 and 11:00–11:30
        ((10, 0, 0), (11, 0, 0), (11, 0, 0), (11, 30, 0), .adjacent),
        // 5. 10:00–10:30 and 10:30–11:00
        ((10, 0, 0), (10, 30, 0), (10, 30, 0), (11, 0, 0), .adjacent),
        // 6. 10:00:30–11:00:15 and 11:00:15–12:00
        ((10, 0, 30), (11, 0, 15), (11, 0, 15), (12, 0, 0), .adjacent),
        // 7. 10:00–11:00 and 11:00:01–12:00
        ((10, 0, 0), (11, 0, 0), (11, 0, 1), (12, 0, 0), .separated(1)),
        // 8. 10:00–11:01 and 11:00–12:00
        ((10, 0, 0), (11, 1, 0), (11, 0, 0), (12, 0, 0), .overlapping(60))
    ])
    func matrix(aStart: (Int, Int, Int), aEnd: (Int, Int, Int), bStart: (Int, Int, Int), bEnd: (Int, Int, Int),
                expected: WorkInterval.Relation) {
        let a = Self.interval(aStart, aEnd)
        let b = Self.interval(bStart, bEnd)
        #expect(a.relation(to: b) == expected)
        #expect(b.relation(to: a) == expected)
        let overlapping = if case .overlapping = expected { true } else { false }
        #expect(a.overlaps(b) == overlapping)
        #expect(b.overlaps(a) == overlapping)
        #expect(a.isAdjacent(to: b) == (expected == .adjacent))
    }

    @Test("10:00–12:00 and 11:00–13:00 overlap by an hour")
    func partialOverlap() {
        let a = Self.interval((10, 0, 0), (12, 0, 0))
        let b = Self.interval((11, 0, 0), (13, 0, 0))
        #expect(a.overlaps(b))
        #expect(a.relation(to: b) == .overlapping(3600))
    }

    // MARK: Events written to Calendar

    @Test("Back-to-back sessions write exactly their recorded times to Calendar by default")
    func exactEventTimes() async throws {
        let clock = TestClock(Self.at(10, 0))
        let env = try TestEnvironment(clock: clock)
        #expect(env.settings.calendarEventTiming == .exact)
        let template = try env.makeTemplate()

        try env.sessionService.start(template: template)
        clock.now = Self.at(11, 0)
        let first = try await env.sessionService.finish()
        try env.sessionService.start(template: template)
        clock.now = Self.at(12, 0)
        let second = try await env.sessionService.finish()

        let events = env.calendarProvider.events.values.map(\.record).sorted { $0.startDate < $1.startDate }
        #expect(events.count == 2)
        #expect(events[0].startDate == Self.at(10, 0))
        #expect(events[0].endDate == Self.at(11, 0))
        #expect(events[1].startDate == Self.at(11, 0))
        #expect(events[1].endDate == Self.at(12, 0))
        #expect(!WorkInterval(start: events[0].startDate, end: events[0].endDate)
            .overlaps(WorkInterval(start: events[1].startDate, end: events[1].endDate)))
        // Each work log is exactly one hour, and neither was changed by the other.
        #expect(first.log.activeDuration == 3600)
        #expect(second.log.activeDuration == 3600)
        #expect(env.persistence.session(id: first.log.id)?.endedAt == Self.at(11, 0))
        #expect(env.persistence.session(id: second.log.id)?.startedAt == Self.at(11, 0))
    }

    @Test("Exact timing keeps seconds; nearest-minute timing rounds only the event, never the work log")
    func roundedEventTimes() async throws {
        let clock = TestClock(Self.at(10, 0, 12))
        let env = try TestEnvironment(clock: clock)
        let template = try env.makeTemplate()

        try env.sessionService.start(template: template)
        clock.now = Self.at(11, 0, 40)
        let first = try await env.sessionService.finish()
        let exact = try #require(env.calendarProvider.events.values.first?.record)
        #expect(exact.startDate == Self.at(10, 0, 12))
        #expect(exact.endDate == Self.at(11, 0, 40))

        env.settings.calendarEventTiming = .nearestMinute
        clock.now = Self.at(11, 0, 52)
        try env.sessionService.start(template: template)
        clock.now = Self.at(12, 0, 29)
        let second = try await env.sessionService.finish()
        let rounded = try #require(env.calendarProvider.events.values.map(\.record).first { $0.url == CalendarOwnership.url(for: second.log.id) })
        #expect(rounded.startDate == Self.at(11, 1))
        #expect(rounded.endDate == Self.at(12, 0))

        // The work logs keep their exact timestamps.
        let recorded = try #require(env.persistence.session(id: second.log.id))
        #expect(recorded.startedAt == Self.at(11, 0, 52))
        #expect(recorded.endedAt == Self.at(12, 0, 29))
        #expect(env.persistence.session(id: first.log.id)?.endedAt == Self.at(11, 0, 40))
    }

    @Test("Rounding never makes sessions that didn't overlap overlap, and makes near-adjacent ones meet")
    func roundingPreservesOrder() {
        let timing = CalendarEventTiming.nearestMinute
        let calendar = TestDates.calendar
        // Ends at 11:00:40, next starts 11:00:52: both round to 11:01 and meet.
        let a = timing.eventInterval(for: Self.interval((10, 0, 12), (11, 0, 40)), calendar: calendar)
        let b = timing.eventInterval(for: Self.interval((11, 0, 52), (12, 0, 0)), calendar: calendar)
        #expect(a.relation(to: b) == .adjacent)
        // Exact minutes are unchanged.
        let exact = Self.interval((10, 0, 0), (11, 0, 0))
        #expect(timing.eventInterval(for: exact, calendar: calendar) == exact)
        // A session shorter than half a minute keeps its exact times.
        let short = Self.interval((10, 0, 10), (10, 0, 25))
        #expect(timing.eventInterval(for: short, calendar: calendar) == short)
        // Exhaustive check at 5-second steps: a.end <= b.start stays non-overlapping.
        for endSecond in stride(from: 0, to: 120, by: 5) {
            for gap in stride(from: 0, to: 90, by: 5) {
                let first = WorkInterval(start: Self.at(10, 0), end: Self.at(11, 0, endSecond))
                let second = WorkInterval(start: first.end.addingTimeInterval(TimeInterval(gap)), end: Self.at(13, 0))
                #expect(!timing.eventInterval(for: first, calendar: calendar)
                    .overlaps(timing.eventInterval(for: second, calendar: calendar)))
            }
        }
    }

    @Test("Applying the timing to existing events updates only owned events whose times differ, once")
    func applyToExistingEvents() async throws {
        let clock = TestClock(Self.at(9, 0, 20))
        let env = try TestEnvironment(clock: clock)
        let template = try env.makeTemplate()
        try env.sessionService.start(template: template)
        clock.now = Self.at(9, 59, 50)
        let completion = try await env.sessionService.finish()
        env.calendarProvider.insertForeignEvent(identifier: "someone-else")
        let foreignBefore = env.calendarProvider.events["someone-else"]?.record

        let sessions = try env.persistence.completedSessions()
        #expect(await env.calendarService.applyEventTimingToExistingEvents(sessions) == (0, 0))

        env.settings.calendarEventTiming = .nearestMinute
        #expect(await env.calendarService.applyEventTimingToExistingEvents(sessions) == (1, 0))
        let event = try #require(env.calendarProvider.events.values.map(\.record).first { $0.url == CalendarOwnership.url(for: completion.log.id) })
        #expect(event.startDate == Self.at(9, 0))
        #expect(event.endDate == Self.at(10, 0))
        #expect(env.calendarProvider.events.count == 2)
        #expect(env.calendarProvider.events["someone-else"]?.record == foreignBefore)
        // Idempotent.
        #expect(await env.calendarService.applyEventTimingToExistingEvents(sessions) == (0, 0))
        #expect(env.persistence.session(id: completion.log.id)?.startedAt == Self.at(9, 0, 20))
    }

    @Test("The event timing setting persists and defaults to exact")
    func settingPersists() throws {
        let suite = "CalendarBoundaryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.calendarEventTiming == .exact)
        #expect(settings.calendarConfiguration.eventTiming == .exact)
        settings.calendarEventTiming = .nearestMinute
        #expect(SettingsStore(defaults: defaults).calendarEventTiming == .nearestMinute)
        settings.calendarEventTiming = .exact
        #expect(SettingsStore(defaults: defaults).calendarEventTiming == .exact)
    }

    // MARK: Editing times

    @Test("Picking a new minute clears hidden seconds; an untouched time keeps them")
    func minuteEditing() {
        let calendar = TestDates.calendar
        let recorded = Self.at(11, 2, 15)
        // The picker reports the new minute with the old seconds still attached.
        #expect(MinuteEditing.pickedTime(original: recorded, picked: Self.at(11, 0, 15), calendar: calendar) == Self.at(11, 0))
        #expect(MinuteEditing.pickedTime(original: recorded, picked: recorded, calendar: calendar) == recorded)
        #expect(MinuteEditing.pickedTime(original: recorded, picked: Self.at(11, 2, 40), calendar: calendar) == recorded)
    }

    @Test("Editing a work log to start where another ends is adjacent, not overlapping")
    func editToAdjacent() async throws {
        let clock = TestClock(Self.at(10, 0, 12))
        let env = try TestEnvironment(clock: clock)
        let template = try env.makeTemplate()
        try env.sessionService.start(template: template)
        clock.now = Self.at(11, 0)
        try await env.sessionService.finish()
        clock.now = Self.at(11, 2, 15)
        try env.sessionService.start(template: template)
        clock.now = Self.at(12, 0)
        let second = try #require(env.persistence.session(id: try await env.sessionService.finish().log.id))
        clock.now = Self.at(13, 0)

        // What the edit sheet stores when 11:02 is changed to 11:00 in the picker.
        let picked = MinuteEditing.pickedTime(original: second.startedAt, picked: Self.at(11, 0, 15))
        #expect(env.sessionService.overlappingWorkLogs(excluding: second, start: picked, end: Self.at(12, 0)).isEmpty)
        // Without clearing the seconds, the hidden 15 seconds would overlap.
        #expect(env.sessionService.overlappingWorkLogs(excluding: second, start: Self.at(10, 59, 45), end: Self.at(12, 0)).count == 1)

        var edit = SessionEdit(session: second)
        edit.startedAt = picked
        try await env.sessionService.edit(second, with: edit)
        let events = env.calendarProvider.events.values.map(\.record).sorted { $0.startDate < $1.startDate }
        #expect(events.map(\.endDate).first == Self.at(11, 0))
        #expect(events.map(\.startDate).last == Self.at(11, 0))
        #expect(events.count == 2)
    }
}
