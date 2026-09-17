import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// The popover shown from the CTL menu bar item.
struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }, sort: \WorkSession.startedAt, order: .reverse)
    private var completedSessions: [WorkSession]

    @State private var showsNoteField = false
    @State private var showsTodaysWork = false
    @State private var showsPriorityEditor = false
    @State private var confirmsCancel = false
    /// The inline form shown in place of the template list, if any.
    @State private var composer: MenuBarComposer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = environment.presentedError {
                errorBanner(error)
            }
            if !environment.sessions.canRecordWork {
                Label("Storage unavailable. Work can’t be recorded.", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let completion = environment.sessions.lastCompletion {
                completionCard(completion)
                Divider()
                appRows
            } else if let recovery = environment.sessions.pendingRecovery {
                recoveryCard(recovery)
                Divider()
                appRows
            } else if let session = environment.sessions.activeSession {
                activeSection(session)
                Divider()
                sessionRows(session)
                Divider()
                appRows
                Divider()
                footer
            } else {
                idleSection
                Divider()
                appRows
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.outerInset)
        .padding(.vertical, 12)
        .frame(width: MenuBarPopoverMetrics.width)
        .confirmationDialog("Cancel this session?", isPresented: $confirmsCancel) {
            Button("Cancel Session", role: .destructive) { environment.cancel() }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("The session won’t appear in Work Logs or Calendar.")
        }
    }

    // MARK: Sections

    private func activeSection(_ session: WorkSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                TemplateIconView(icon: session.templateSymbolName, color: session.templateColor, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.templateName)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    CategoryLabel(name: session.category)
                    // Worded chips on their own line, so Urgent and Important
                    // read at a glance; symbols only if even that is too narrow.
                    ViewThatFits(in: .horizontal) {
                        PriorityChips(priority: session.taskPriority, size: .small)
                        PriorityMarkers(priority: session.taskPriority, size: 12)
                    }
                    TagChips(tags: Array(session.tags.prefix(1)))
                }
                Spacer(minLength: 4)
                SessionStateBadge(state: session.state)
            }
            .accessibilityElement(children: .combine)

            LiveDurationText(session: session, now: environment.clock.now, font: .system(size: 42, weight: .bold, design: .rounded))
            Text("Started at \(session.startedAt.shortTime)")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if session.state == .paused {
                    Button { environment.resume() } label: {
                        Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { environment.pause() } label: {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { environment.finish() } label: {
                    Label("Finish Work", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityHint("Ends the session, saves it to Work Logs, and adds it to Calendar")
            }
            .controlSize(.large)

            if environment.pausedForSleepNotice {
                Label("Paused while your Mac was asleep.", systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
        .padding(.top, 2)
    }

    private var idleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ready to work")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Choose a template to start the timer.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
            .padding(.top, 2)

            switch composer {
            case .quickTask:
                MenuBarQuickTaskForm { composer = nil }
            case .startTemplate(let id) where templates.contains(where: { $0.id == id && $0.isLive }):
                if let template = templates.first(where: { $0.id == id }) {
                    MenuBarStartForm(template: template) { composer = nil }
                }
            case .startTemplate, nil:
                // A template deleted while its start form was open falls back to the list.
                MenuRowButton(title: "Quick New Task…", symbol: PrioritySymbols.quickTask, shortcut: "⌘T") {
                    composer = .quickTask
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!environment.sessions.canRecordWork)

                if templates.isEmpty {
                    Button("Create a Template…") {
                        environment.show(.templates, openWindow: openWindow)
                        dismiss()
                    }
                    .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
                } else {
                    VStack(spacing: 2) {
                        ForEach(templates.prefix(9)) { template in
                            TemplateMenuRow(template: template) {
                                environment.start(template)
                            } onStartWithPriority: {
                                composer = .startTemplate(template.id)
                            } onEdit: {
                                environment.selectedTemplateID = template.id
                                environment.show(.templates, openWindow: openWindow)
                                dismiss()
                            }
                            .disabled(!environment.sessions.canRecordWork)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRows(_ session: WorkSession) -> some View {
        VStack(spacing: 1) {
            Menu {
                ForEach(templates) { template in
                    Button { environment.changeTemplate(to: template) } label: {
                        Label(template.name, systemImage: template.symbolName)
                    }
                    .disabled(template.id == session.templateID)
                }
            } label: {
                MenuRowLabel(title: "Change Template", symbol: "arrow.left.arrow.right", showsChevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            MenuRowButton(title: showsPriorityEditor ? "Hide Category and Priority" : "Change Category and Priority",
                          symbol: PrioritySymbols.section) {
                showsPriorityEditor.toggle()
            }
            if showsPriorityEditor {
                HStack(spacing: 10) {
                Label("Category", systemImage: WorkCategory.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 78, alignment: .leading)
                CategoryPicker(selection: Binding(
                    get: { session.category },
                    set: { environment.updateCategory($0) }
                ), compact: true, keepsUnlisted: true)
                    .frame(maxWidth: 170, alignment: .leading)
            }
                .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
                // Matches the indent of the Urgent and Important rows below.
                .padding(.leading, 22)
                .padding(.top, 4)
                TaskPriorityPicker(
                    priority: Binding(
                        get: { session.taskPriority },
                        set: { environment.updateTaskPriority($0) }
                    ),
                    labelWidth: 78,
                    compact: true
                )
                .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
                .padding(.vertical, 4)
            }

            MenuRowButton(title: showsNoteField ? "Hide Note" : "Add Note", symbol: "note.text.badge.plus", shortcut: "⌘N") {
                showsNoteField.toggle()
            }
            .keyboardShortcut("n", modifiers: .command)
            if showsNoteField {
                AddNoteField(autofocus: true)
                    .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
                    .padding(.vertical, 4)
            }
            MenuRowButton(title: "Cancel Session…", symbol: "xmark.circle") {
                confirmsCancel = true
            }
        }
    }

    private var appRows: some View {
        VStack(spacing: 1) {
            MenuRowButton(title: "Today’s Work", symbol: "clock", trailing: DurationFormatting.short(todayTotal)) {
                showsTodaysWork.toggle()
            }
            .accessibilityValue(DurationFormatting.spoken(todayTotal))
            if showsTodaysWork {
                todaysWork
            }
            MenuRowButton(title: "Work Logs", symbol: "list.bullet.rectangle") {
                environment.show(.workLogs, openWindow: openWindow)
                dismiss()
            }
            MenuRowButton(title: "Open Calendar Time Logger", symbol: "macwindow", shortcut: "⌘O") {
                environment.openMainWindow(openWindow)
                dismiss()
            }
            .keyboardShortcut("o", modifiers: .command)
            MenuRowButton(title: "Settings…", symbol: "gearshape", shortcut: "⌘,") {
                openSettings()
                NSApp.activate()
                dismiss()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRowButton(title: "Quit Calendar Time Logger", symbol: "power", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            // The logo image includes the macOS icon margin, so it isn't clipped.
            Image("BrandLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Calendar Time Logger")
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Version \(Bundle.main.shortVersion)").font(.caption).foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button("Show App") {
                environment.openMainWindow(openWindow)
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset - 3)
        .padding(.top, 2)
    }

    private func recoveryCard(_ session: WorkSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Active Session Detected", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            TemplateLabel(name: session.templateName, icon: session.templateSymbolName, color: session.templateColor)
            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Resume Session") { environment.resolveRecovery(.resume) }
                    .buttonStyle(.borderedProminent)
                Button("Finish Work") { environment.resolveRecovery(.finishNow) }
                    .buttonStyle(.bordered)
            }
            Button("Cancel Session", role: .destructive) { environment.resolveRecovery(.cancel) }
                .buttonStyle(.link)
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
    }

    /// Compact “Work Completed” confirmation for sessions finished from the menu bar.
    private func completionCard(_ completion: SessionCompletion) -> some View {
        let log = completion.log
        return VStack(alignment: .leading, spacing: 8) {
            Label("Work Completed", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            TemplateLabel(name: log.templateName, icon: log.templateIcon, color: log.templateColor)
            HStack(spacing: 8) {
                CategoryLabel(name: log.category)
                PriorityChips(priority: log.taskPriority, size: .small)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("Time").foregroundStyle(.secondary)
                    Text("\(log.startedAt.shortTime) – \(log.endedAt.shortTime)")
                }
                GridRow {
                    Text("Active Work").foregroundStyle(.secondary)
                    Text(DurationFormatting.short(log.activeDuration)).fontWeight(.semibold)
                }
            }
            .font(.callout)
            .monospacedDigit()
            CompletionCalendarStatus(completion: completion, compact: true)
                .font(.callout)
            HStack {
                if completion.calendarOutcome?.succeeded == true {
                    Button("View in Calendar") { environment.openCalendarApp() }
                }
                Spacer()
                Button("Done") { environment.sessions.lastCompletion = nil }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
        .accessibilityElement(children: .contain)
    }

    private var todaysWork: some View {
        let totals = WorkAnalytics.templateTotals(todayLogs)
        return VStack(alignment: .leading, spacing: 6) {
            if totals.isEmpty {
                Text("No work recorded today yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(totals) { total in
                HStack(spacing: 8) {
                    TemplateIconView(icon: total.icon, color: total.color, size: 18)
                    Text(total.name)
                        .lineLimit(1)
                    Spacer()
                    Text(DurationFormatting.short(total.duration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.callout)
        .padding(.leading, 34)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
    }

    private func errorBanner(_ error: PresentableError) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.callout.weight(.semibold))
                if !error.message.isEmpty {
                    Text(error.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                environment.presentedError = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
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

    private var todayTotal: TimeInterval {
        WorkAnalytics.totalActiveDuration(todayLogs)
    }
}

/// Shared sizes for the menu bar popover.
enum MenuBarPopoverMetrics {
    /// Compact, but wide enough for “Open Calendar Time Logger ⌘O” without clipping.
    static let width: CGFloat = 288
    static let outerInset: CGFloat = 6
    /// Horizontal padding inside rows; headers use the same inset so text aligns.
    static let rowInset: CGFloat = 10
    static let rowCornerRadius: CGFloat = 8
    static let templateIconSize: CGFloat = 32
    static let utilityIconWidth: CGFloat = 22
}

/// A template row: click to start work; the chevron offers more actions.
private struct TemplateMenuRow: View {
    let template: WorkTemplate
    let action: () -> Void
    let onStartWithPriority: () -> Void
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    TemplateIconView(icon: template.symbolName, color: template.color, size: MenuBarPopoverMetrics.templateIconSize)
                    Text(template.name)
                        .font(.title3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    PriorityMarkers(priority: template.taskPriority, size: 10)
                }
                .padding(.leading, MenuBarPopoverMetrics.rowInset)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Start \(template.name)")
            .accessibilityLabel("Start \(template.name)")

            Menu {
                Button(action: action) { Label("Start Work", systemImage: "play.fill") }
                Button(action: onStartWithPriority) { Label("Start with Category and Priority…", systemImage: PrioritySymbols.section) }
                Button(action: onEdit) { Label("Edit Template…", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: MenuBarPopoverMetrics.templateIconSize + 10)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 2)
            .accessibilityLabel("More actions for \(template.name)")
        }
        .background(isHovering ? Color.primary.opacity(0.09) : .clear, in: .rect(cornerRadius: MenuBarPopoverMetrics.rowCornerRadius))
        .onHover { isHovering = $0 }
    }
}

/// The visual content of a menu-like row.
struct MenuRowLabel: View {
    let title: String
    let symbol: String
    var trailing: String?
    var shortcut: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: MenuBarPopoverMetrics.utilityIconWidth)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let shortcut {
                Text(shortcut)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
        .padding(.vertical, 7)
        .contentShape(.rect)
    }
}

/// A full-width, menu-like row button with hover highlight.
struct MenuRowButton: View {
    let title: String
    let symbol: String
    var trailing: String?
    var shortcut: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, symbol: symbol, trailing: trailing, shortcut: shortcut)
                .background(isHovering ? Color.primary.opacity(0.09) : .clear, in: .rect(cornerRadius: MenuBarPopoverMetrics.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The inline form shown in the popover in place of the template list.
enum MenuBarComposer: Equatable {
    case quickTask
    case startTemplate(UUID)
}

/// Quick New Task inside the menu bar popover: a name, the category, the two
/// priority choices, and Start Work. Kept to the popover width.
private struct MenuBarQuickTaskForm: View {
    @Environment(AppEnvironment.self) private var environment
    let onClose: () -> Void

    @State private var draft = QuickTaskDraft()
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick New Task")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("Task", text: $draft.name, prompt: Text("What are you working on?"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($nameIsFocused)
                .onSubmit(start)
                .accessibilityLabel("Task name")
            HStack(spacing: 10) {
                Label("Category", systemImage: WorkCategory.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // Wider than the priority labels so the menu lines up with the segmented controls.
                    .frame(width: 108, alignment: .leading)
                CategoryPicker(selection: $draft.category, compact: true)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            TaskPriorityPicker(priority: $draft.taskPriority, labelWidth: 86, compact: true)
            HStack(spacing: 8) {
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button {
                    start()
                } label: {
                    Label("Start Work", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid || !environment.sessions.canRecordWork)
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
        .padding(.vertical, 2)
        .onAppear { nameIsFocused = true }
    }

    private func start() {
        guard draft.isValid else { return }
        environment.startQuickTask(draft)
        onClose()
    }
}

/// Starts one template from the popover after a look at its category and priority.
private struct MenuBarStartForm: View {
    @Environment(AppEnvironment.self) private var environment
    let template: WorkTemplate
    let onClose: () -> Void

    @State private var priority: TaskPriority
    @State private var category: String

    init(template: WorkTemplate, onClose: @escaping () -> Void) {
        self.template = template
        self.onClose = onClose
        _priority = State(initialValue: template.taskPriority)
        _category = State(initialValue: template.category)
    }

    var body: some View {
        if template.isLive {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TemplateIconView(icon: template.symbolName, color: template.color, size: 28)
                Text(template.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Label("Category", systemImage: WorkCategory.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    // Wider than the priority labels so the menu lines up with the segmented controls.
                    .frame(width: 108, alignment: .leading)
                CategoryPicker(selection: $category, compact: true)
                    .frame(maxWidth: 170, alignment: .leading)
            }
            TaskPriorityPicker(priority: $priority, labelWidth: 86, compact: true)
            HStack(spacing: 8) {
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button {
                    // The template may have been deleted from the main window meanwhile.
                    if template.isLive { environment.start(template, priority: priority, category: category) }
                    onClose()
                } label: {
                    Label("Start Work", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!environment.sessions.canRecordWork)
            }
        }
        .padding(.horizontal, MenuBarPopoverMetrics.rowInset)
        .padding(.vertical, 2)
    }
}
