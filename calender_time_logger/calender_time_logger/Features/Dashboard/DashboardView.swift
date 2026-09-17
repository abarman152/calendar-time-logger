import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Prioritizes the current session, then today's progress and work.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }, sort: \WorkSession.startedAt, order: .reverse)
    private var completedSessions: [WorkSession]
    @State private var confirmsCancel = false
    @State private var noteFocusRequest = 0
    @State private var showsNewTemplate = false
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let density = environment.settings.density
        let now = environment.clock.now
        ScrollView {
            VStack(alignment: .leading, spacing: density.sectionSpacing) {
                header(now: now)
                banners

                if let recovery = environment.sessions.pendingRecovery {
                    RecoveryCard(session: recovery)
                }

                // Two columns when there's room for both at a comfortable width.
                if contentWidth >= 780 {
                    HStack(alignment: .top, spacing: density.sectionSpacing) {
                        primaryCard
                        sideColumn
                            .frame(width: 320)
                    }
                } else {
                    VStack(spacing: density.sectionSpacing) {
                        primaryCard
                        sideColumn
                    }
                }

                todaysWork
            }
            .padding(28)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 56 } action: { contentWidth = $0 }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                StartWorkMenu(templates: templates, title: "New Session")
                    .disabled(environment.sessions.activeSession != nil)
                    .help(environment.sessions.activeSession != nil ? "Finish the current session before starting another." : "Start a session")
            }
        }
        .confirmationDialog("Cancel this session?", isPresented: $confirmsCancel) {
            Button("Cancel Session", role: .destructive) { environment.cancel() }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("The timer stops and the session won’t appear in Work Logs, analytics, or Calendar.")
        }
        .sheet(isPresented: $showsNewTemplate) {
            TemplateEditorSheet { created in
                environment.selectedTemplateID = created.id
                showsNewTemplate = false
            } onCancel: {
                showsNewTemplate = false
            }
        }
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Greeting.text(for: now))
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(Greeting.subtitle(for: now))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()), systemImage: "calendar")
                    .foregroundStyle(.secondary)
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if let storeError = environment.persistence.storeError {
            Banner(symbol: "externaldrive.badge.exclamationmark", tint: .red,
                   title: storeError.errorDescription ?? "Storage unavailable",
                   message: [storeError.failureReason, storeError.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
        }
        let needsAttention = completedSessions.filter { $0.calendarSyncStatus.needsAttention }.count
        if needsAttention > 0 {
            Banner(symbol: "calendar.badge.exclamationmark", tint: .orange,
                   title: needsAttention == 1 ? "1 work log isn’t in Calendar" : "\(needsAttention) work logs aren’t in Calendar",
                   message: "Your work is saved. Review and retry from the Calendar section.") {
                Button("Review") { environment.selectedSection = .calendar }
            }
        }
        if environment.pausedForSleepNotice, environment.sessions.activeSession?.state == .paused {
            Banner(symbol: "moon.zzz", tint: .secondary, title: "Paused while your Mac was asleep",
                   message: "Resume when you’re back to work.")
        }
    }

    // MARK: Primary card

    @ViewBuilder
    private var primaryCard: some View {
        if let session = environment.sessions.activeSession, environment.sessions.pendingRecovery == nil {
            currentSession(session)
        } else {
            readyToWork
        }
    }

    private func currentSession(_ session: WorkSession) -> some View {
        let now = environment.clock.now
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Currently Working")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SessionStateBadge(state: session.state)
                Menu {
                    Menu {
                        ForEach(templates) { template in
                            Button { environment.changeTemplate(to: template) } label: {
                                Label(template.name, systemImage: template.symbolName)
                            }
                            .disabled(template.id == session.templateID)
                        }
                    } label: {
                        Label("Change Template", systemImage: "arrow.left.arrow.right")
                    }
                    Button { environment.isChangePriorityPresented = true } label: {
                        Label("Change Category and Priority…", systemImage: PrioritySymbols.section)
                    }
                    Button { noteFocusRequest += 1 } label: { Label("Add Note", systemImage: "square.and.pencil") }
                    Divider()
                    Button(role: .destructive) { confirmsCancel = true } label: { Label("Cancel Session…", systemImage: "xmark.circle") }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Session actions")
            }

            HStack(spacing: 16) {
                TemplateIconView(icon: session.templateSymbolName, color: session.templateColor, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.templateName)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 10) {
                        Text("Started at \(session.startedAt.shortTime)")
                            .foregroundStyle(.secondary)
                        CategoryLabel(name: session.category, font: .body)
                    }
                    HStack(spacing: 6) {
                        PriorityChips(priority: session.taskPriority, showsNeither: true)
                        TagChips(tags: session.tags)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            LiveDurationText(session: session, now: now, font: .system(size: 72, weight: .bold, design: .rounded))
                .fixedSize()

            if session.pausedDuration(at: now) >= 60 || session.state == .paused {
                Label("Paused \(DurationFormatting.short(session.pausedDuration(at: now))) · Wall clock \(DurationFormatting.short(session.wallClockDuration(at: now)))",
                      systemImage: "pause.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SessionPrimaryButtons(session: session)

            AddNoteField(prompt: "Add a note about what you’re working on…", focusRequest: noteFocusRequest)

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }

            HStack(spacing: 16) {
                Menu {
                    ForEach(templates) { template in
                        Button { environment.changeTemplate(to: template) } label: {
                            Label(template.name, systemImage: template.symbolName)
                        }
                        .disabled(template.id == session.templateID)
                    }
                } label: {
                    Label("Change Template", systemImage: "arrow.left.arrow.right")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize()
                Button {
                    environment.isChangePriorityPresented = true
                } label: {
                    Label("Task Priority", systemImage: PrioritySymbols.section)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize()
                .help("Change Urgent and Important for this session")
                Button("Cancel Session…") { confirmsCancel = true }
                    .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 22)
    }

    private var readyToWork: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to work")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Start a template when you begin. When you finish, your work is logged and added to Calendar.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No Templates", systemImage: "square.grid.2x2")
                } description: {
                    Text("Create a template for each kind of work you do.")
                } actions: {
                    Button("Create Template") { showsNewTemplate = true }
                    Button("Quick New Task…") { environment.requestQuickTask() }
                }
            } else {
                HStack(spacing: 12) {
                    StartWorkSplitButton(templates: templates)
                        .fixedSize()
                    Button {
                        environment.requestQuickTask()
                    } label: {
                        Label("Quick New Task", systemImage: PrioritySymbols.quickTask)
                            .padding(.horizontal, 6)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .disabled(!environment.sessions.canRecordWork || environment.sessions.activeSession != nil)
                    .help("Start work without a template (⌥⌘N)")
                }

                Text("Recent Templates")
                    .font(.headline)
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(recentTemplates) { template in
                        TemplateStartButton(template: template)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 22)
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(spacing: environment.settings.density.sectionSpacing) {
            TodaysProgressCard(logs: todayLogs, goalMinutes: environment.settings.dailyGoalMinutes)
            quickActions
        }
    }

    private var quickActions: some View {
        SectionCard("Quick Actions") {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                if environment.sessions.activeSession != nil {
                    Button { noteFocusRequest += 1 } label: { Label("Add Note", systemImage: "square.and.pencil") }
                        .buttonStyle(TileButtonStyle(prominent: true))
                    Button { environment.isChangePriorityPresented = true } label: {
                        Label("Task Priority", systemImage: PrioritySymbols.section)
                    }
                    .buttonStyle(TileButtonStyle())
                    .help("Change Urgent and Important for this session")
                } else {
                    Button { environment.requestQuickTask() } label: {
                        Label("Quick New Task", systemImage: PrioritySymbols.quickTask)
                    }
                    .buttonStyle(TileButtonStyle(prominent: true))
                    .help("Start work without a template (⌥⌘N)")
                    Button { showsNewTemplate = true } label: { Label("New Template", systemImage: "plus.square") }
                        .buttonStyle(TileButtonStyle())
                }
                Button { environment.requestExport() } label: { Label("Export", systemImage: "tablecells") }
                    .buttonStyle(TileButtonStyle())
                    .help("Export Work Logs to an Excel workbook")
                Button { environment.openCalendarApp() } label: { Label("View Calendar", systemImage: "calendar") }
                    .buttonStyle(TileButtonStyle())
                Button { environment.selectedSection = .workLogs } label: { Label("Work Logs", systemImage: "list.bullet.rectangle") }
                    .buttonStyle(TileButtonStyle())
            }
        }
    }

    // MARK: Today's work

    private var todaysWork: some View {
        let logs = todayLogs.sorted { $0.startedAt < $1.startedAt }
        return SectionCard("Today’s Work", symbol: "list.bullet.rectangle") {
            if !logs.isEmpty {
                Button {
                    environment.selectedSection = .workLogs
                } label: {
                    Label("View All", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.link)
            }
        } content: {
            if logs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No work logged")
                        .font(.headline)
                    Text("Start a template to begin tracking your time.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 0) {
                    ForEach(logs) { log in
                        HStack(spacing: 12) {
                            TemplateIconView(icon: log.templateIcon, color: log.templateColor, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(log.templateName).fontWeight(.medium)
                                    PriorityMarkers(priority: log.taskPriority)
                                }
                                Text("\(log.isInProgress ? "\(log.startedAt.shortTime) – In Progress" : "\(log.startedAt.shortTime) – \(log.endedAt.shortTime)") · \(log.category)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            Text(DurationFormatting.short(log.activeDuration))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Total").font(.headline)
                            if environment.sessions.activeSession != nil {
                                Text("Includes the session in progress.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(DurationFormatting.short(WorkAnalytics.totalActiveDuration(logs)))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Data

    private var todayLogs: [WorkLog] {
        let now = environment.clock.now
        var logs = completedSessions.map { WorkLog(session: $0) }
        if let active = environment.sessions.activeSession {
            logs.append(WorkLog(session: active, now: now))
        }
        return WorkAnalytics.logs(logs, in: WorkAnalytics.dayInterval(containing: now))
    }

    /// Templates ordered by most recent use, then by template order.
    private var recentTemplates: [WorkTemplate] {
        AppEnvironment.templatesByRecentUse(templates, sessions: completedSessions)
            .prefix(8)
            .map { $0 }
    }
}

/// Today's total with a per-template ring and the daily goal.
private struct TodaysProgressCard: View {
    let logs: [WorkLog]
    let goalMinutes: Int

    var body: some View {
        let totals = WorkAnalytics.templateTotals(logs)
        let total = WorkAnalytics.totalActiveDuration(logs)
        SectionCard("Today’s Progress") {
            HStack(alignment: .center, spacing: 18) {
                ring(totals: totals, total: total)
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 8) {
                    if totals.isEmpty {
                        Text("No work yet today.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(totals.prefix(4)) { item in
                        HStack(spacing: 6) {
                            Image(systemName: TemplateSymbol.displayName(item.icon))
                                .foregroundStyle(item.color.color)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(item.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(DurationFormatting.short(item.duration))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if goalMinutes > 0 {
                Divider()
                let goal = TimeInterval(goalMinutes * 60)
                let fraction = min(1, total / goal)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Daily Goal", systemImage: "target")
                        Spacer()
                        Text(DurationFormatting.short(goal)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    HStack(spacing: 10) {
                        ProgressView(value: fraction)
                            .tint(.accentColor)
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Daily goal \(DurationFormatting.spoken(goal)), \(fraction.formatted(.percent.precision(.fractionLength(0)))) complete")
            }
        }
    }

    private func ring(totals: [TemplateTotal], total: TimeInterval) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)
            if total > 0 {
                ForEach(Array(segments(totals, total: total).enumerated()), id: \.offset) { _, segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 0) {
                Text(total < 1 ? "0m" : DurationFormatting.short(total))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today’s total")
        .accessibilityValue(DurationFormatting.spoken(total))
    }

    private func segments(_ totals: [TemplateTotal], total: TimeInterval) -> [(start: Double, end: Double, color: Color)] {
        var start = 0.0
        let gap = totals.count > 1 ? 0.006 : 0
        return totals.map { item in
            let length = item.duration / total
            defer { start += length }
            return (start, max(start, start + length - gap), item.color.color)
        }
    }
}

private struct TemplateStartButton: View {
    @Environment(AppEnvironment.self) private var environment
    let template: WorkTemplate
    @State private var isHovering = false

    var body: some View {
        Button {
            environment.start(template)
        } label: {
            HStack(spacing: 10) {
                TemplateIconView(icon: template.symbolName, color: template.color, size: 36)
                Text(template.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: isHovering ? "play.fill" : "chevron.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(Color.primary.opacity(isHovering ? 0.07 : 0.03), in: .rect(cornerRadius: Metrics.cardCornerRadius - 2))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius - 2).strokeBorder(isHovering ? template.color.color.opacity(0.7) : Color.primary.opacity(0.1)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(!environment.sessions.canRecordWork)
        .accessibilityLabel("Start \(template.name)")
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

struct Banner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    init(symbol: String, tint: Color, title: String, message: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                if !message.isEmpty {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions
        }
        .padding(12)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
