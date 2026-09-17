import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Creates or edits a template. Changes are applied on Save.
struct TemplateEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    let template: WorkTemplate?
    var onCreate: ((WorkTemplate) -> Void)?
    var onCancel: (() -> Void)?
    /// Asks the owner to confirm and delete this template. The editor never
    /// deletes the model it is showing.
    var onDelete: (() -> Void)?

    @State private var draft: WorkTemplateDraft
    @State private var tagsText: String
    @State private var validationMessage: String?
    @State private var contentWidth: CGFloat = 0

    init(template: WorkTemplate?, onCreate: ((WorkTemplate) -> Void)? = nil, onCancel: (() -> Void)? = nil,
         onDelete: (() -> Void)? = nil) {
        self.template = template
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.onDelete = onDelete
        let initial = template?.draft ?? WorkTemplateDraft(
            menuBarConfiguration: MenuBarConfiguration(displayMode: AppEnvironment.shared.settings.defaultDisplayMode)
        )
        _draft = State(initialValue: initial)
        _tagsText = State(initialValue: TagParsing.display(initial.tags))
    }

    private var isNew: Bool { template == nil }
    private var hasChanges: Bool {
        guard let template else { return true }
        guard template.isLive else { return false }
        var current = draft
        current.tags = TagParsing.parse(tagsText)
        return current != template.draft
    }

    var body: some View {
        // A deleted template can't be read; the owner removes this view right after.
        if template?.isLive ?? true {
            editor
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if contentWidth >= 760 {
                        HStack(alignment: .top, spacing: 16) {
                            leftColumn
                            rightColumn.frame(width: 330)
                        }
                    } else {
                        VStack(spacing: 16) {
                            leftColumn
                            rightColumn
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1000, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 40 } action: { contentWidth = $0 }
            }
            Divider()
            // Outside the scroll view, so Cancel and Save are always on screen.
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    // MARK: Header

    private var header: some View {
        // Side by side when there is room; otherwise the actions move under the
        // title, so a narrow window never squeezes the template's name.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                headerTitle
                Spacer(minLength: 12)
                headerActions
            }
            VStack(alignment: .leading, spacing: 12) {
                headerTitle
                HStack(spacing: 8) { headerActions }
            }
        }
        .controlSize(.large)
    }

    private var headerTitle: some View {
        HStack(alignment: .center, spacing: 14) {
            TemplateIconView(icon: draft.icon, color: draft.color, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(draft.normalizedName.isEmpty ? (isNew ? "New Template" : "Untitled") : draft.normalizedName)
                        .font(.title.weight(.semibold))
                        .lineLimit(1)
                    PriorityChips(priority: draft.taskPriority)
                }
                HStack(spacing: 8) {
                    CategoryLabel(name: WorkCategory.stored(draft.category), font: .callout)
                    Text(draft.notes.isEmpty ? "Describe how this kind of work is recorded." : draft.notes)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if let template {
            Button { environment.start(template) } label: { Label("Start Work", systemImage: "play.fill") }
                .disabled(environment.sessions.activeSession != nil || hasChanges)
                .help(hasChanges ? "Save your changes first" : "Start a session with this template")
            Button("Duplicate") { duplicate(template) }
                .disabled(hasChanges)
                .help(hasChanges ? "Save or revert your changes first" : "Create a copy of this template")
            if let onDelete {
                Button("Delete", role: .destructive, action: onDelete)
                    .accessibilityLabel("Delete template \(template.name)")
            }
        }
    }

    // MARK: Columns

    private var leftColumn: some View {
        VStack(spacing: 16) {
            SectionCard("Basic Information") {
                FormRow("Name") {
                    TextField("Name", text: $draft.name, prompt: Text("Software Engineering"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                FormRow("Icon") {
                    SymbolPickerField(symbol: $draft.icon, color: draft.color)
                }
                FormRow("Category") {
                    CategoryPicker(selection: $draft.category, fallback: categoryFallback)
                        .fixedSize()
                }
            }

            TaskPriorityCard(
                priority: $draft.taskPriority,
                subtitle: "Set the default priority for sessions started from this template.",
                footnote: "These values are used as defaults when starting a new session. You can change them for an individual session without changing the template."
            )

            SectionCard("Appearance") {
                FormRow("Icon Color") {
                    ColorSwatchRow(color: $draft.color)
                }
                FormRow("Menu Bar Background") {
                    OptionalColorSwatchRow(color: $draft.menuBarConfiguration.backgroundColor, automaticTitle: "None")
                }
            }

            SectionCard("Recording") {
                FormRow("Calendar") {
                    CalendarPicker(
                        title: "Calendar",
                        selection: $draft.calendarIdentifier,
                        calendars: environment.calendar.writableCalendars,
                        fallbackTitle: "Default (\(defaultCalendarName))"
                    )
                    .labelsHidden()
                }
                if environment.calendar.authorization != .fullAccess {
                    Text("Connect Apple Calendar in the Calendar section to choose a calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                FormRow("Tags") {
                    TextField("Tags", text: $tagsText, prompt: Text("#coding #development"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                FormRow("Notes") {
                    TextField("Notes", text: $draft.notes, prompt: Text("Optional description"), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .labelsHidden()
                }
            }

            EventAppearanceCard(draft: $draft)
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 16) {
            MenuBarPreviewCard(draft: draft, showsSeconds: environment.settings.menuBarShowsSeconds)

            SectionCard("Menu Bar Settings") {
                Toggle("Show in menu bar", isOn: $draft.menuBarConfiguration.isVisible)
                Group {
                    Picker("Display", selection: $draft.menuBarConfiguration.displayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    if draft.menuBarConfiguration.displayMode == .nameOnly {
                        Toggle("Show icon with name", isOn: $draft.menuBarConfiguration.showsIconWithName)
                    }
                    if draft.menuBarConfiguration.displayMode.showsName && draft.menuBarConfiguration.displayMode.showsDuration {
                        LabeledContent("Separator") {
                            TextField("Separator", text: $draft.menuBarConfiguration.separator)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .labelsHidden()
                        }
                    }
                    if showsIconColor {
                        OptionalColorMenu(title: "Icon color", color: $draft.menuBarConfiguration.iconColor)
                    }
                    if draft.menuBarConfiguration.displayMode.showsName {
                        OptionalColorMenu(title: "Name color", color: $draft.menuBarConfiguration.nameColor)
                    }
                    if draft.menuBarConfiguration.displayMode.showsDuration {
                        OptionalColorMenu(title: "Duration color", color: $draft.menuBarConfiguration.durationColor)
                    }
                }
                .disabled(!draft.menuBarConfiguration.isVisible)
                Text(draft.menuBarConfiguration.backgroundColor == nil
                     ? "Automatic colors match the menu bar in light and dark appearance."
                     : "Automatic colors use white or black, whichever is legible on the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionCard("Notifications") {
                Toggle("Notify when session starts", isOn: $draft.notificationBehavior.notifyOnStart)
                Toggle("Notify when session ends", isOn: $draft.notificationBehavior.notifyOnFinish)
                Picker("Long session reminder", selection: $draft.notificationBehavior.reminderIntervalMinutes) {
                    Text("Off").tag(Int?.none)
                    ForEach(NotificationBehavior.reminderChoices, id: \.self) { minutes in
                        Text("Every \(DurationFormatting.short(TimeInterval(minutes * 60)))").tag(Int?.some(minutes))
                    }
                }
                if !environment.settings.notificationsEnabled {
                    Text("Notifications are turned off in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            Spacer()
            if isNew {
                Button("Cancel") { onCancel?() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Revert") { revert() }
                    .disabled(!hasChanges)
            }
            Button(isNew ? "Create Template" : "Save Changes") { save() }
                .accessibilityIdentifier(isNew ? "create-template" : "save-template")
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
        }
        .controlSize(.large)
    }

    // MARK: Helpers

    private var showsIconColor: Bool {
        let config = draft.menuBarConfiguration
        return config.displayMode.requiresIcon || (config.displayMode == .nameOnly && config.showsIconWithName)
    }

    /// A deleted category falls back to where the template's own category went
    /// (a delete moves templates first), or General for a new template.
    private func categoryFallback() -> String {
        guard let template, template.isLive else { return WorkCategory.defaultName }
        return template.category
    }

    private var defaultCalendarName: String {
        environment.calendar.calendar(withIdentifier: environment.settings.defaultCalendarIdentifier)?.title
            ?? environment.calendar.systemDefaultCalendar?.title
            ?? "System Default"
    }

    private func save() {
        var final = draft
        final.tags = TagParsing.parse(tagsText)
        do {
            if let template {
                try environment.persistence.updateTemplate(template, with: final)
                draft = template.draft
                tagsText = TagParsing.display(template.tags)
            } else {
                let created = try environment.persistence.createTemplate(final)
                onCreate?(created)
            }
            validationMessage = nil
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func revert() {
        guard let template else { return }
        draft = template.draft
        tagsText = TagParsing.display(template.tags)
        validationMessage = nil
    }

    private func duplicate(_ template: WorkTemplate) {
        environment.perform {
            let copy = try environment.persistence.duplicateTemplate(template)
            environment.selectedTemplateID = copy.id
        }
    }
}

/// A labelled row inside an editor card.
private struct FormRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Palette swatches plus the system color picker.
private struct ColorSwatchRow: View {
    @Binding var color: HexColor

    var body: some View {
        ChipFlowLayout(spacing: 7) {
            ForEach(TemplatePalette.colors, id: \.name) { entry in
                Swatch(color: entry.color, name: entry.name, isSelected: entry.color == color, size: 20) {
                    color = entry.color
                }
            }
            ColorPicker("Custom Color", selection: Binding(
                get: { color.color },
                set: { if let rgb = HexColor($0) { color = rgb } }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Custom color")
        }
    }
}

/// Swatches for an optional color, with an explicit “none/auto” choice.
private struct OptionalColorSwatchRow: View {
    @Binding var color: HexColor?
    var automaticTitle = "Auto"

    var body: some View {
        ChipFlowLayout(spacing: 7) {
            Button {
                color = nil
            } label: {
                Image(systemName: "circle.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(color == nil ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(automaticTitle)
            .accessibilityLabel(automaticTitle)
            .accessibilityAddTraits(color == nil ? .isSelected : [])
            ForEach(TemplatePalette.colors.prefix(8), id: \.name) { entry in
                Swatch(color: entry.color, name: entry.name, isSelected: entry.color == color, size: 20) {
                    color = entry.color
                }
            }
            ColorPicker("Custom Color", selection: Binding(
                get: { color?.color ?? .accentColor },
                set: { color = HexColor($0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Custom color")
        }
    }
}

/// A compact optional color control for the narrow menu bar card.
private struct OptionalColorMenu: View {
    let title: String
    @Binding var color: HexColor?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Picker(title, selection: Binding(
                    get: { color.flatMap { TemplatePalette.name(for: $0) } ?? (color == nil ? "Auto" : "Custom") },
                    set: { name in
                        if name == "Auto" {
                            color = nil
                        } else if let entry = TemplatePalette.colors.first(where: { $0.name == name }) {
                            color = entry.color
                        } else if color == nil {
                            // “Custom…” starts from the menu bar's text color; the well then edits it.
                            color = .white
                        }
                    }
                )) {
                    Text("Auto").tag("Auto")
                    Divider()
                    ForEach(TemplatePalette.colors, id: \.name) { entry in
                        Label {
                            Text(entry.name)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(entry.color.color)
                        }
                        .tag(entry.name)
                    }
                    Text("Custom…").tag("Custom")
                }
                .labelsHidden()
                .fixedSize()
                if color != nil {
                    ColorPicker(title, selection: Binding(
                        get: { color?.color ?? .primary },
                        set: { color = HexColor($0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .help("Custom \(title.lowercased())")
                }
            }
        }
    }
}

/// Live preview of the menu bar item on a light, dark, or system menu bar.
private struct MenuBarPreviewCard: View {
    let draft: WorkTemplateDraft
    let showsSeconds: Bool
    @State private var background: AppearancePreference = .system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snapshot = MenuBarSessionSnapshot(
            templateName: draft.normalizedName.isEmpty ? "Template" : draft.normalizedName,
            templateIcon: draft.normalizedIcon,
            state: .active,
            activeDuration: 1 * 3600 + 24 * 60 + 37,
            configuration: draft.menuBarConfiguration
        )
        let presentation = MenuBarFormatter.presentation(for: snapshot, showsSeconds: showsSeconds)
        let scheme = background.colorScheme ?? colorScheme

        SectionCard("Menu Bar Preview") {
            HStack {
                Spacer()
                Group {
                    if let symbol = presentation.symbol {
                        Image(systemName: symbol.rawValue)
                    } else {
                        MenuBarSegmentsView(segments: presentation.segments, backgroundColor: presentation.backgroundColor, fontSize: 15,
                                            truncatesName: true)
                    }
                }
                .foregroundStyle(.primary)
                .environment(\.colorScheme, scheme)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(scheme == .light ? Color(white: 0.92) : Color(white: 0.14), in: .rect(cornerRadius: Metrics.controlCornerRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Menu bar preview: \(presentation.symbol == nil ? [presentation.iconSymbolName.map { SymbolPickerView.readableName($0) + " icon" }, presentation.plainText].compactMap { $0 }.joined(separator: ", ") : "generic timer symbol")")

            Picker("Preview Background", selection: $background) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

/// Calendar event appearance: what EventKit supports, stated plainly.
private struct EventAppearanceCard: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var draft: WorkTemplateDraft

    var body: some View {
        let calendar = resolvedCalendar
        SectionCard("Calendar Event Appearance") {
            FormRow("Event Color") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(calendar?.color?.color ?? Color.secondary)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text(calendar.map { "Follows the “\($0.title)” calendar" } ?? "Follows the event’s calendar")
                }
            }
            Text("Apple Calendar colors each event by the calendar it belongs to. EventKit has no per-event color, so a template can’t give its events their own color. To show this template’s work in a distinct color, choose a calendar with that color under Recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let color = calendar?.color, color != draft.color {
                Button("Match Icon Color to Calendar") { draft.color = color }
                    .help("Sets this template’s icon color to the calendar’s color. The calendar itself isn’t changed.")
            }
        }
    }

    private var resolvedCalendar: CalendarInfo? {
        let service = environment.calendar
        return service.calendar(withIdentifier: draft.calendarIdentifier)
            ?? service.calendar(withIdentifier: environment.settings.defaultCalendarIdentifier)
            ?? service.systemDefaultCalendar
    }
}
