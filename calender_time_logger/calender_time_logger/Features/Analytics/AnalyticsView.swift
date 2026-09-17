import CalendarTimeLoggerKit
import Charts
import SwiftData
import SwiftUI

/// The date range every figure on the Analytics screen is calculated from.
enum AnalyticsRange: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case last7
    case thisMonth
    case last30

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .last7: "Last 7 Days"
        case .thisMonth: "This Month"
        case .last30: "Last 30 Days"
        }
    }

    /// The interval, ending at the end of the day containing `now` so work
    /// recorded later today is always included.
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, end: endOfToday)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return DateInterval(start: start, end: endOfToday)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return DateInterval(start: start, end: endOfToday)
        case .last7, .last30:
            let days = self == .last7 ? 7 : 30
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: endOfToday)
        }
    }

    /// How many days the trend chart draws for this range.
    func dayCount(now: Date, calendar: Calendar = .current) -> Int {
        let interval = self.interval(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day ?? 0
        return max(1, days + 1)
    }

    /// Whether a daily trend is worth drawing (a single day has no trend).
    var showsTrend: Bool { self != .today }
}

/// Work summary, category, priority, and template breakdowns, and trends, all
/// for the selected date range.
struct AnalyticsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }, sort: \WorkSession.startedAt, order: .reverse)
    private var sessions: [WorkSession]
    @State private var range: AnalyticsRange = Self.initialRange
    @State private var showsTemplatePriority = false
    @State private var showsCategoryBreakdown = Self.initiallyExpandsCategories

    private static var initialRange: AnalyticsRange {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if DemoMode.current != nil, let index = arguments.firstIndex(of: "-demoAnalyticsRange"),
           arguments.indices.contains(index + 1), let range = AnalyticsRange(rawValue: arguments[index + 1]) {
            return range
        }
        #endif
        return .thisWeek
    }

    private static var initiallyExpandsCategories: Bool {
        #if DEBUG
        return DemoMode.current != nil && ProcessInfo.processInfo.arguments.contains("-demoExpandCategories")
        #else
        return false
        #endif
    }

    var body: some View {
        let now = Date()
        // One projection per render, reused by every section below.
        let logs = sessions.map { WorkLog(session: $0) }
        let inRange = WorkAnalytics.logs(logs, in: range.interval(now: now))
        let summary = WorkAnalytics.summary(inRange)

        ScrollView {
            VStack(alignment: .leading, spacing: environment.settings.density.sectionSpacing) {
                rangeHeader
                summaryTiles(summary, logs: logs, now: now)

                if logs.isEmpty {
                    ContentUnavailableView("No Data Yet", systemImage: "chart.bar.xaxis",
                                           description: Text("Analytics appear after you finish your first session."))
                        .frame(maxWidth: .infinity)
                        .card()
                } else {
                    goalCard(logs: logs, now: now)
                    categoryCard(inRange)
                    priorityCard(inRange, summary: summary)
                    templateCard(inRange)
                    if range.showsTrend {
                        trendCard(WorkAnalytics.dailyTotals(logs, endingOn: now, count: range.dayCount(now: now)), now: now)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Analytics")
        .navigationSubtitle(range.title)
    }

    // MARK: Summary

    private var rangeHeader: some View {
        Picker("Range", selection: $range) {
            ForEach(AnalyticsRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Date range")
    }

    private func summaryTiles(_ summary: WorkSummary, logs: [WorkLog], now: Date) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            StatTile(title: "Total Work", value: DurationFormatting.short(summary.totalActiveDuration),
                     detail: range.title, symbol: "clock")
            StatTile(title: "Sessions", value: "\(summary.sessionCount)",
                     detail: summary.sessionCount == 1 ? "Completed session" : "Completed sessions", symbol: "list.bullet.rectangle")
            StatTile(title: "Average Session",
                     value: summary.sessionCount == 0 ? "—" : DurationFormatting.short(summary.averageSessionDuration),
                     detail: summary.sessionCount == 0 ? "No sessions yet" : "Active work per session", symbol: "chart.bar.xaxis")
            StatTile(title: "Streak", value: "\(WorkAnalytics.currentStreak(logs, now: now)) days",
                     detail: "Consecutive days with work", symbol: "flame")
        }
    }

    @ViewBuilder
    private func goalCard(logs: [WorkLog], now: Date) -> some View {
        let goalMinutes = environment.settings.dailyGoalMinutes
        if goalMinutes > 0 {
            let today = WorkAnalytics.logs(logs, in: WorkAnalytics.dayInterval(containing: now))
            let total = WorkAnalytics.totalActiveDuration(today)
            let goal = TimeInterval(goalMinutes * 60)
            let fraction = min(1, total / goal)
            SectionCard("Today’s Goal", symbol: "target") {
                HStack(spacing: 12) {
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                    Text("\(DurationFormatting.short(total)) of \(DurationFormatting.short(goal))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today’s goal")
                .accessibilityValue("\(DurationFormatting.spoken(total)) of \(DurationFormatting.spoken(goal)), \(fraction.formatted(.percent.precision(.fractionLength(0)))) complete")
            }
        }
    }

    // MARK: Categories

    /// Work by category for the selected range only. Grouped by the category
    /// recorded on each session, so history reads as it was recorded.
    private func categoryCard(_ logs: [WorkLog]) -> some View {
        let totals = WorkAnalytics.categoryTotals(logs)
        return SectionCard("Work by Category", symbol: WorkCategory.symbolName) {
            if totals.isEmpty {
                ContentUnavailableView {
                    Label("No category data yet", systemImage: WorkCategory.symbolName)
                } description: {
                    Text("Start a work session to begin building your category history.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Chart(totals) { total in
                    BarMark(
                        x: .value("Hours", total.duration / 3600),
                        y: .value("Category", total.name)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(3)
                    .annotation(position: .trailing) {
                        Text(total.share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityLabel(total.name)
                    .accessibilityValue("\(DurationFormatting.spoken(total.duration)), \(total.share.formatted(.percent.precision(.fractionLength(0))))")
                }
                .chartXAxisLabel("Hours")
                .chartYAxis {
                    AxisMarks(preset: .extended, position: .leading)
                }
                .frame(height: CGFloat(totals.count) * 32 + 30)

                VStack(spacing: 0) {
                    ForEach(totals) { total in
                        Divider()
                        HStack(spacing: 10) {
                            Label(total.name, systemImage: WorkCategory.symbolName)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(sessionCount(total.sessionCount))
                                .foregroundStyle(.secondary)
                            Text(total.share.formatted(.percent.precision(.fractionLength(0))))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(DurationFormatting.short(total.duration))
                                .fontWeight(.medium)
                                .frame(width: 70, alignment: .trailing)
                        }
                        .monospacedDigit()
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }

                DisclosureGroup(isExpanded: $showsCategoryBreakdown) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(totals) { total in
                            CategoryBreakdown(total: total)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Templates and Task Priority by Category").font(.callout)
                }
            }
        }
    }

    // MARK: Task priority

    @ViewBuilder
    private func priorityCard(_ logs: [WorkLog], summary: WorkSummary) -> some View {
        let totals = WorkAnalytics.priorityTotals(logs)
        SectionCard("Task Priority", symbol: PrioritySymbols.section) {
            if logs.isEmpty {
                ContentUnavailableView("No Priority Data", systemImage: PrioritySymbols.quadrants,
                                       description: Text("No work was recorded in this range."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(totals) { total in
                        QuadrantTile(total: total)
                    }
                }

                Chart(totals) { total in
                    BarMark(
                        x: .value("Hours", total.duration / 3600),
                        y: .value("Priority", total.quadrant.shortTitle)
                    )
                    .foregroundStyle(total.quadrant.color.color.gradient)
                    .annotation(position: .trailing) {
                        Text(total.duration < 60 ? "" : DurationFormatting.short(total.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(total.quadrant.title)
                    .accessibilityValue(DurationFormatting.spoken(total.duration))
                }
                .chartXAxisLabel("Hours")
                .chartYAxis {
                    AxisMarks(preset: .extended, position: .leading)
                }
                .frame(height: 4 * 34 + 30)

                Divider()

                HStack(spacing: 24) {
                    priorityTotal("Urgent", symbol: PrioritySymbols.urgent, tint: PrioritySymbols.urgentTint,
                                  duration: summary.urgentDuration, total: summary.totalActiveDuration)
                    priorityTotal("Important", symbol: PrioritySymbols.important, tint: PrioritySymbols.importantTint,
                                  duration: summary.importantDuration, total: summary.totalActiveDuration)
                    Spacer(minLength: 0)
                }
                Text("A session can be both urgent and important, so those two totals overlap. The four combinations above do not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                templatePriorityDisclosure(logs)
            }
        }
    }

    private func priorityTotal(_ title: String, symbol: String, tint: Color, duration: TimeInterval, total: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(duration < 1 ? "0m" : DurationFormatting.short(duration))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(total > 0 ? (duration / total).formatted(.percent.precision(.fractionLength(0))) : "0%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time on \(title.lowercased()) work")
        .accessibilityValue(DurationFormatting.spoken(duration))
    }

    private func templatePriorityDisclosure(_ logs: [WorkLog]) -> some View {
        let rows = WorkAnalytics.templatePriorityTotals(logs)
        return DisclosureGroup(isExpanded: $showsTemplatePriority) {
            VStack(spacing: 0) {
                HStack {
                    Text("Template").foregroundStyle(.secondary)
                    Spacer()
                    Text("Urgent").foregroundStyle(PrioritySymbols.urgentTint).frame(width: 80, alignment: .trailing)
                    Text("Important").foregroundStyle(PrioritySymbols.importantTint).frame(width: 80, alignment: .trailing)
                    Text("Total").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .padding(.vertical, 6)
                ForEach(rows) { row in
                    Divider()
                    HStack {
                        TemplateLabel(name: row.template.name, icon: row.template.icon, color: row.template.color, iconSize: 20)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.urgentDuration < 60 ? "—" : DurationFormatting.short(row.urgentDuration))
                            .frame(width: 80, alignment: .trailing)
                        Text(row.importantDuration < 60 ? "—" : DurationFormatting.short(row.importantDuration))
                            .frame(width: 80, alignment: .trailing)
                        Text(DurationFormatting.short(row.template.duration))
                            .fontWeight(.medium)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.callout)
                    .monospacedDigit()
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.template.name): \(DurationFormatting.spoken(row.urgentDuration)) urgent, \(DurationFormatting.spoken(row.importantDuration)) important, \(DurationFormatting.spoken(row.template.duration)) in total")
                }
            }
            .padding(.top, 4)
        } label: {
            Text("By Template").font(.callout)
        }
    }

    // MARK: Templates and trend

    private func templateCard(_ logs: [WorkLog]) -> some View {
        let totals = WorkAnalytics.templateTotals(logs)
        let sum = totals.reduce(0) { $0 + $1.duration }
        return SectionCard("Work by Template", symbol: "square.grid.2x2") {
            if totals.isEmpty {
                Text("No work recorded in this range.").foregroundStyle(.secondary)
            } else {
                Chart(totals) { total in
                    BarMark(
                        x: .value("Hours", total.duration / 3600),
                        y: .value("Template", total.name)
                    )
                    .foregroundStyle(total.color.color.gradient)
                    .annotation(position: .trailing) {
                        Text(DurationFormatting.short(total.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(total.name)
                    .accessibilityValue(DurationFormatting.spoken(total.duration))
                }
                .chartXAxisLabel("Hours")
                .frame(height: CGFloat(max(1, totals.count)) * 36 + 30)

                ForEach(totals) { total in
                    HStack {
                        TemplateLabel(name: total.name, icon: total.icon, color: total.color, iconSize: 22)
                        Spacer()
                        Text(sessionCount(total.sessionCount))
                            .foregroundStyle(.secondary)
                        Text(sum > 0 ? (total.duration / sum).formatted(.percent.precision(.fractionLength(0))) : "")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        Text(DurationFormatting.short(total.duration))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func trendCard(_ days: [DailyTotal], now: Date) -> some View {
        struct Point: Identifiable {
            let day: Date
            let template: TemplateTotal
            var id: String { "\(day.timeIntervalSince1970)-\(template.key)" }
        }
        let points = days.flatMap { day in day.templates.map { Point(day: day.day, template: $0) } }
        let legend = Dictionary(points.map { ($0.template.name, $0.template.color.color) }, uniquingKeysWith: { first, _ in first })
        let names = legend.keys.sorted()
        let stride = days.count > 10 ? 5 : 1

        return SectionCard("Daily Active Work", symbol: "chart.bar.xaxis") {
            if points.isEmpty {
                Text("No work recorded in this range.").foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Hours", point.template.duration / 3600)
                    )
                    .foregroundStyle(by: .value("Template", point.template.name))
                    .accessibilityLabel("\(point.day.formatted(date: .abbreviated, time: .omitted)), \(point.template.name)")
                    .accessibilityValue(DurationFormatting.spoken(point.template.duration))
                }
                .chartForegroundStyleScale(domain: names, range: names.map { legend[$0] ?? .accentColor })
                .chartYAxisLabel("Hours")
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: stride)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
                    }
                }
                .chartXScale(domain: (days.first?.day ?? now)...(Calendar.current.date(byAdding: .day, value: 1, to: days.last?.day ?? now) ?? now))
                .frame(height: 240)
            }
        }
    }

    private func sessionCount(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }
}

/// One category's templates and priority combinations, for the disclosure in
/// Work by Category.
private struct CategoryBreakdown: View {
    let total: CategoryTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(total.name, systemImage: WorkCategory.symbolName)
                    .font(.headline)
                Spacer()
                Text(DurationFormatting.short(total.duration))
                    .font(.headline)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            ForEach(total.templates) { template in
                HStack {
                    TemplateLabel(name: template.name, icon: template.icon, color: template.color, iconSize: 18)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(DurationFormatting.short(template.duration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
                .padding(.leading, 22)
                .accessibilityElement(children: .combine)
            }
            // Only combinations with recorded work are listed, to keep this compact.
            let used = total.quadrants.filter { $0.sessionCount > 0 }
            HStack(spacing: 14) {
                ForEach(used) { quadrant in
                    HStack(spacing: 4) {
                        Image(systemName: quadrant.quadrant.symbolName)
                            .foregroundStyle(quadrant.quadrant.color.color)
                            .accessibilityHidden(true)
                        Text(quadrant.quadrant.shortTitle)
                            .foregroundStyle(.secondary)
                        Text(DurationFormatting.short(quadrant.duration))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(quadrant.quadrant.title), \(DurationFormatting.spoken(quadrant.duration))")
                }
            }
            .font(.caption)
            .padding(.leading, 22)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Metrics.controlCornerRadius))
    }
}

/// One of the four priority combinations, as a card.
private struct QuadrantTile: View {
    let total: PriorityTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(total.quadrant.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: total.quadrant.symbolName)
                    .foregroundStyle(total.quadrant.color.color)
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // An unused combination reads as 0m, not as "less than a minute".
                Text(total.duration < 1 ? "0m" : DurationFormatting.short(total.duration))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(total.share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(total.sessionCount == 1 ? "1 session" : "\(total.sessionCount) sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(total.quadrant.color.color.opacity(0.10), in: .rect(cornerRadius: Metrics.controlCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius)
                .strokeBorder(total.quadrant.color.color.opacity(0.25), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(total.quadrant.title)
        .accessibilityValue("\(DurationFormatting.spoken(total.duration)), \(total.share.formatted(.percent.precision(.fractionLength(0)))) of the range, \(total.sessionCount) sessions")
    }
}
