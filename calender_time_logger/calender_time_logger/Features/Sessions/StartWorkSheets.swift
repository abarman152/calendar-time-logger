import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Start Work with a look at the task priority first.
///
/// The template supplies the defaults; changing them here applies to this
/// session only and never edits the template.
struct StartSessionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]
    let onClose: () -> Void

    @State private var templateID: UUID?
    @State private var priority = TaskPriority.default
    @State private var category = WorkCategory.defaultName
    @State private var didLoad = false

    private var selected: WorkTemplate? {
        templates.first { $0.id == templateID } ?? templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                templateRow
                if selected != nil {
                    HStack(spacing: 12) {
                        Text("Category")
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                        CategoryPicker(selection: $category)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label("Session Priority", systemImage: PrioritySymbols.section)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 4)
                        if let selected {
                            if priority != selected.taskPriority || !WorkCategory.matches(category, selected.category) {
                                Button("Use Template Defaults") {
                                    priority = selected.taskPriority
                                    category = selected.category
                                }
                                .controlSize(.small)
                                .help("Template defaults: \(selected.category), \(selected.taskPriority.quadrant.sentence.lowercased())")
                            } else {
                                Text("Template defaults")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    TaskPriorityPicker(priority: $priority)
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Work")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Check the template, category, and priority, then start the timer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    @ViewBuilder
    private var templateRow: some View {
        if templates.isEmpty {
            ContentUnavailableView {
                Label("No Templates", systemImage: "square.grid.2x2")
            } description: {
                Text("Create a template, or start a Quick New Task instead.")
            }
        } else {
            HStack(spacing: 12) {
                Text("Template")
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                Menu {
                    ForEach(templates) { template in
                        Button { select(template) } label: {
                            Label(template.name, systemImage: template.symbolName)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if let selected {
                            TemplateIconView(icon: selected.symbolName, color: selected.color, size: 24)
                            Text(selected.name).lineLimit(1)
                        } else {
                            Text("Choose a template")
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .menuIndicator(.hidden)
                .controlSize(.large)
                .accessibilityLabel("Template")
                .accessibilityValue(selected?.name ?? "None")
            }
        }
    }

    private var footnote: String {
        guard let selected else { return "The category and both values are recorded with the session." }
        let defaults = selected.taskPriority
        return priority == defaults && WorkCategory.matches(category, selected.category)
            ? "These are \(selected.name)’s defaults. They are recorded with this session."
            : "Changed for this session only. \(selected.name) still starts in \(selected.category), \(defaults.quadrant.sentence.lowercased())."
    }

    private var footer: some View {
        HStack {
            Button("Quick New Task…") {
                onClose()
                environment.requestQuickTask()
            }
            .buttonStyle(.link)
            .help("Start work without a template")
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button {
                start()
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil || !environment.sessions.canRecordWork)
        }
        .controlSize(.large)
        .padding(20)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let template = environment.preferredTemplate(from: templates) ?? templates.first
        templateID = template?.id
        priority = template?.taskPriority ?? .default
        category = template?.category ?? WorkCategory.defaultName
    }

    /// Choosing another template adopts its defaults, as if it had been picked first.
    private func select(_ template: WorkTemplate) {
        templateID = template.id
        priority = template.taskPriority
        category = template.category
    }

    private func start() {
        guard let selected else { return }
        environment.start(selected, priority: priority, category: category)
        onClose()
    }
}

/// Quick New Task: name the work, classify it, and start — no template needed.
struct QuickTaskSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let onClose: () -> Void

    @State private var draft = QuickTaskDraft()
    @State private var tagsText = ""
    @State private var showsMoreOptions = false
    @FocusState private var nameIsFocused: Bool

    private var canStart: Bool {
        var candidate = draft
        candidate.tags = TagParsing.parse(tagsText)
        return candidate.isValid && environment.sessions.canRecordWork && environment.sessions.activeSession == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Task")
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    TextField("Task", text: $draft.name, prompt: Text("What are you working on?"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .labelsHidden()
                        .focused($nameIsFocused)
                        .onSubmit { if canStart { start() } }
                        .accessibilityLabel("Task name")
                }

                HStack(spacing: 12) {
                    Text("Category")
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    CategoryPicker(selection: $draft.category)
                        .fixedSize()
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Task Priority", systemImage: PrioritySymbols.section)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    TaskPriorityPicker(priority: $draft.taskPriority)
                }

                DisclosureGroup(isExpanded: $showsMoreOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Tags")
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            TextField("Tags", text: $tagsText, prompt: Text("#review #urgent"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                        }
                        HStack(alignment: .top, spacing: 12) {
                            Text("Notes")
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            TextField("Notes", text: $draft.notes, prompt: Text("Optional"), axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                                .labelsHidden()
                        }
                        HStack(spacing: 12) {
                            Text("Calendar")
                                .foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            CalendarPicker(
                                title: "Calendar",
                                selection: $draft.calendarIdentifier,
                                calendars: environment.calendar.writableCalendars,
                                fallbackTitle: "Default (\(defaultCalendarName))"
                            )
                            .labelsHidden()
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("More Options").font(.callout)
                }
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 460)
        .onAppear { nameIsFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: PrioritySymbols.quickTask)
                .font(.system(size: 22))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(.purple.opacity(0.14), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick New Task")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Start work right away. No template is created.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if !environment.sessions.canRecordWork {
                Label("Storage unavailable. Work can’t be recorded.", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button {
                start()
            } label: {
                Label("Start Work", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
            .help(canStart ? "Starts the timer" : "Give the task a name first")
        }
        .controlSize(.large)
        .padding(20)
    }

    private var defaultCalendarName: String {
        environment.calendar.calendar(withIdentifier: environment.settings.defaultCalendarIdentifier)?.title
            ?? environment.calendar.systemDefaultCalendar?.title
            ?? "System Default"
    }

    private func start() {
        var final = draft
        final.tags = TagParsing.parse(tagsText)
        guard final.isValid else { return }
        environment.startQuickTask(final)
        onClose()
    }
}

/// Changes the priority of the session in progress. The session keeps whatever
/// it ends with, and that is what the Work Log records.
struct ChangeTaskPrioritySheet: View {
    @Environment(AppEnvironment.self) private var environment
    let session: WorkSession
    let onClose: () -> Void

    @State private var priority: TaskPriority
    @State private var category: String

    init(session: WorkSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        _priority = State(initialValue: session.taskPriority)
        _category = State(initialValue: session.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Category and Priority")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Applies to this session only; the template isn’t changed. The Work Log records the values it ends with.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TemplateLabel(name: session.templateName, icon: session.templateSymbolName, color: session.templateColor, iconSize: 26)
            HStack(spacing: 10) {
                Label("Category", systemImage: WorkCategory.symbolName)
                    // Lines the menu up with the Urgent and Important controls below.
                    .frame(width: 125, alignment: .leading)
                CategoryPicker(selection: $category, keepsUnlisted: true)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            TaskPriorityPicker(priority: $priority)
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if priority != session.taskPriority { environment.updateTaskPriority(priority) }
                    if category != session.category { environment.updateCategory(category) }
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(priority == session.taskPriority && category == session.category)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 420)
    }
}
