import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@Suite("Work Logs and analytics")
struct WorkLogAnalyticsTests {
    static let engineering = UUID()
    static let research = UUID()

    func log(_ templateID: UUID?, _ name: String, day: Int, from: (Int, Int), to: (Int, Int),
             pausedMinutes: Double = 0, notes: String = "", tags: [String] = [], status: CalendarSyncStatus = .synced) -> WorkLog {
        let start = TestDates.date(2026, 9, day, from.0, from.1)
        let end = TestDates.date(2026, 9, day, to.0, to.1)
        let pauses = pausedMinutes > 0 ? [PauseInterval(start: start.addingTimeInterval(60), end: start.addingTimeInterval(60 + pausedMinutes * 60))] : []
        return WorkLog(templateID: templateID, templateName: name, templateIcon: "laptopcomputer", templateColor: TemplatePalette.colors[0].color,
                       timing: SessionTiming(startedAt: start, endedAt: end, pauses: pauses), now: end,
                       notes: notes, tags: tags, calendarSyncStatus: status)
    }

    var sample: [WorkLog] {
        [
            log(Self.engineering, "Software Engineering", day: 15, from: (10, 0), to: (12, 24), pausedMinutes: 25, notes: "Parser work", tags: ["coding"]),
            log(Self.research, "Research", day: 15, from: (14, 0), to: (15, 42), tags: ["papers"], status: .failed),
            log(nil, "Documentation", day: 15, from: (17, 0), to: (17, 48), tags: ["writing"]),
            log(Self.engineering, "Software Engineering", day: 14, from: (9, 0), to: (11, 0), tags: ["coding"])
        ]
    }

    @Test("Logs expose correct durations and template association")
    func durations() {
        let entry = sample[0]
        #expect(entry.templateID == Self.engineering)
        #expect(entry.wallClockDuration == 2 * 3600 + 24 * 60)
        #expect(entry.pausedDuration == 25 * 60)
        #expect(entry.activeDuration == 3600 + 59 * 60)
    }

    @Test("Groups by start day, newest first, sorted within a day")
    func grouping() {
        let groups = WorkLogQuery.groupByDay(sample.shuffled(), calendar: TestDates.calendar)
        #expect(groups.count == 2)
        #expect(groups[0].day == TestDates.date(2026, 9, 15))
        #expect(groups[0].logs.map(\.templateName) == ["Software Engineering", "Research", "Documentation"])
        #expect(groups[0].totalActiveDuration == (119 + 102 + 48) * 60)
        #expect(groups[1].logs.count == 1)
    }

    @Test("Filters by template, tag, sync status, and date")
    func filtering() {
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(templateID: Self.engineering)).count == 2)
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(tag: "papers")).map(\.templateName) == ["Research"])
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(syncStatus: .failed)).count == 1)
        let day = DateInterval(start: TestDates.date(2026, 9, 14), end: TestDates.date(2026, 9, 15))
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(dateInterval: day)).count == 1)
        #expect(!WorkLogFilter().isActive)
        #expect(WorkLogFilter(tag: "coding").isActive)
    }

    @Test("Search matches name, notes, and tags")
    func search() {
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(searchText: "research")).count == 1)
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(searchText: "parser")).count == 1)
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(searchText: "#writing")).map(\.templateName) == ["Documentation"])
        #expect(WorkLogQuery.filter(sample, with: WorkLogFilter(searchText: "zzz")).isEmpty)
        #expect(WorkLogQuery.allTags(in: sample) == ["coding", "papers", "writing"])
    }

    @Test("Today total and per-template weekly totals")
    func totals() {
        let now = TestDates.date(2026, 9, 15, 18, 0)
        let today = WorkAnalytics.logs(sample, in: WorkAnalytics.dayInterval(containing: now, calendar: TestDates.calendar))
        #expect(WorkAnalytics.totalActiveDuration(today) == (119 + 102 + 48) * 60)

        let week = WorkAnalytics.logs(sample, in: WorkAnalytics.weekInterval(containing: now, calendar: TestDates.calendar))
        let totals = WorkAnalytics.templateTotals(week)
        #expect(totals.first?.name == "Software Engineering")
        #expect(totals.first?.duration == TimeInterval((119 + 120) * 60))
        #expect(totals.first?.sessionCount == 2)
        #expect(totals.map(\.name) == ["Software Engineering", "Research", "Documentation"])
    }

    @Test("Daily totals cover each requested day, including empty ones")
    func dailyTotals() {
        let days = WorkAnalytics.dailyTotals(sample, endingOn: TestDates.date(2026, 9, 15, 12), count: 3, calendar: TestDates.calendar)
        #expect(days.map(\.day) == [TestDates.date(2026, 9, 13), TestDates.date(2026, 9, 14), TestDates.date(2026, 9, 15)])
        #expect(days[0].total == 0)
        #expect(days[1].total == 120 * 60)
    }

    @Test("Streak counts consecutive days")
    func streak() {
        #expect(WorkAnalytics.currentStreak(sample, now: TestDates.date(2026, 9, 15, 20), calendar: TestDates.calendar) == 2)
        #expect(WorkAnalytics.currentStreak(sample, now: TestDates.date(2026, 9, 16, 9), calendar: TestDates.calendar) == 2)
        #expect(WorkAnalytics.currentStreak(sample, now: TestDates.date(2026, 9, 18, 9), calendar: TestDates.calendar) == 0)
    }
}
