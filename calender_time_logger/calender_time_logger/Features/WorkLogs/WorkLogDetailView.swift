import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Details and actions for one completed session.
///
/// Editing and deleting are requested from the owner (`WorkLogsView`), which
/// presents the sheet and the confirmation. This view never deletes the model
/// it shows.
struct WorkLogDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]
    let session: WorkSession
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isSyncing = false
    @State private var message: String?

    var body: some View {
        // A deleted model can't be read; the owner removes this view right after.
        if session.isLive {
            let log = WorkLog(session: session)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(log)
                    detailsCard(log)
                    actionsCard(log)
                    footnote
                }
                .padding(16)
            }
        }
    }

    private func header(_ log: WorkLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TemplateIconView(icon: log.templateIcon, color: log.templateColor, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(log.templateName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                Text("\(log.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(log.startedAt.shortTime) – \(log.endedAt.shortTime)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                PriorityChips(priority: log.taskPriority)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button("Edit", action: onEdit)
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityLabel("Edit \(log.templateName) work log")
        }
    }

    private func detailsCard(_ log: WorkLog) -> some View {
        VStack(spacing: 0) {
            CardRow(title: "Duration", symbol: "clock") {
                Text(DurationFormatting.spoken(log.wallClockDuration).capitalizedFirst)
            }
            Divider()
            CardRow(title: "Active Work", symbol: "bolt") {
                Text(DurationFormatting.short(log.activeDuration)).fontWeight(.semibold)
            }
            Divider()
            CardRow(title: "Paused", symbol: "pause.circle") {
                Text(log.pauseCount > 0
                     ? "\(DurationFormatting.short(log.pausedDuration)) (\(log.pauseCount) \(log.pauseCount == 1 ? "pause" : "pauses"))"
                     : "None")
            }
            Divider()
            CardRow(title: "Template", symbol: "square.grid.2x2") {
                Text(log.templateID == nil ? "\(log.templateName) (quick task)" : log.templateName)
            }
            Divider()
            CardRow(title: "Category", symbol: WorkCategory.symbolName) {
                Text(log.category)
            }
            Divider()
            CardRow(title: "Task Priority", symbol: PrioritySymbols.section) {
                VStack(alignment: .leading, spacing: 6) {
                    PriorityValueRows(priority: log.taskPriority, labelWidth: 72)
                    PriorityQuadrantLabel(quadrant: log.taskPriority.quadrant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            CardRow(title: "Tags", symbol: "tag") {
                if log.tags.isEmpty {
                    Text("No tags").foregroundStyle(.secondary)
                } else {
                    TagChips(tags: log.tags, wraps: true)
                }
            }
            Divider()
            CardRow(title: "Notes", symbol: "note.text") {
                if log.notes.isEmpty {
                    Text("No notes").foregroundStyle(.secondary)
                } else {
                    Text(log.notes).textSelection(.enabled)
                }
            }
            Divider()
            CardRow(title: "Calendar Event", symbol: "calendar") {
                VStack(alignment: .leading, spacing: 4) {
                    if session.calendarSyncStatus == .synced, let calendarName {
                        Label("Created in \(calendarName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Calendar: event created in \(calendarName)")
                    } else {
                        SyncStatusLabel(status: session.calendarSyncStatus)
                    }
                    if let syncMessage = session.calendarSyncMessage {
                        Text(syncMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if session.calendarSyncStatus != .synced {
                        Button(isSyncing ? "Adding…" : (session.calendarSyncStatus == .notSynced ? "Add to Calendar" : "Retry")) { retry() }
                            .controlSize(.small)
                            .disabled(isSyncing || !environment.settings.calendarSyncEnabled)
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .card(padding: 12)
    }

    private func actionsCard(_ log: WorkLog) -> some View {
        SectionCard("Actions") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                Button(action: onEdit) { Label("Edit Entry", systemImage: "pencil") }
                    .buttonStyle(TileButtonStyle())
                Button { environment.openCalendarApp() } label: { Label("View in Calendar", systemImage: "calendar") }
                    .buttonStyle(TileButtonStyle())
                    .disabled(session.calendarSyncStatus != .synced)
                    .help("Opens the Calendar app")
                Menu {
                    ForEach(templates) { template in
                        Button { changeTemplate(to: template) } label: {
                            Label(template.name, systemImage: template.symbolName)
                        }
                        .disabled(template.id == session.templateID)
                    }
                } label: {
                    Label("Change Template", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.button)
                .buttonStyle(TileButtonStyle())
                .menuIndicator(.hidden)
                .disabled(templates.isEmpty)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Delete \(log.templateName) work log")
            }
        }
    }

    private var footnote: some View {
        Label(session.calendarSyncStatus == .synced
              ? "This work log is saved on this Mac and linked to its Calendar event."
              : "This work log is saved on this Mac.",
              systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: Metrics.cardCornerRadius))
    }

    private var calendarName: String? {
        environment.calendar.calendar(withIdentifier: session.eventCalendarIdentifier ?? session.calendarIdentifier)?.title
    }

    private func retry() {
        isSyncing = true
        Task {
            _ = await environment.sessions.retryCalendarSync(session)
            isSyncing = false
        }
    }

    private func changeTemplate(to template: WorkTemplate) {
        Task {
            do {
                let outcome = try await environment.sessions.reassignTemplate(of: session, to: template)
                if case .failed(let error) = outcome {
                    message = "Template changed. \(error.errorDescription ?? "Calendar wasn’t updated.")"
                } else {
                    message = nil
                }
            } catch {
                environment.presentedError = PresentableError(error, title: "Couldn’t change the template")
            }
        }
    }
}

/// Editing for one completed session: times, category, priority, tags, notes, and calendar.
struct WorkLogEditSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let session: WorkSession
    let onClose: () -> Void

    @State private var edit: SessionEdit
    @State private var tagsText: String
    @State private var isSaving = false
    @State private var message: String?

    init(session: WorkSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        _edit = State(initialValue: SessionEdit(session: session))
        _tagsText = State(initialValue: TagParsing.display(session.tags))
    }

    private var hasChanges: Bool {
        guard session.isLive else { return false }
        var current = edit
        current.tags = TagParsing.parse(tagsText)
        return current != SessionEdit(session: session)
    }

    var body: some View {
        if session.isLive {
            form
        } else {
            VStack {
                ContentUnavailableView("Work Log Deleted", systemImage: "trash",
                                       description: Text("This work log no longer exists."))
                Button("Close", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .padding(.bottom, 16)
            }
            .frame(width: 480, height: 320)
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TemplateLabel(name: session.templateName, icon: session.templateSymbolName, color: session.templateColor, iconSize: 32)
                        .font(.title3.weight(.semibold))
                }
                Section {
                    DatePicker("Started", selection: minuteBinding(\.startedAt))
                    DatePicker("Finished", selection: minuteBinding(\.endedAt), in: edit.startedAt...)
                    if session.pauses.contains(where: { $0.start < edit.startedAt || ($0.end ?? .distantFuture) > edit.endedAt }) {
                        Text("Pauses outside the new time range will be trimmed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !overlaps.isEmpty {
                        Label {
                            Text(overlapMessage)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .font(.callout)
                        .accessibilityIdentifier("overlap-warning")
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("A session that ends at 11:00 and one that starts at 11:00 are back to back, not overlapping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Category") {
                        CategoryPicker(selection: $edit.category, keepsUnlisted: true)
                            .fixedSize()
                    }
                } header: {
                    Text("Category")
                } footer: {
                    Text("Changes this work log only. Templates aren’t changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TaskPriorityPicker(priority: $edit.taskPriority, labelWidth: 110)
                } header: {
                    Label("Task Priority", systemImage: PrioritySymbols.section)
                } footer: {
                    Text("Changes this recorded session only. The template’s default priority isn’t changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Details") {
                    TextField("Tags", text: $tagsText, prompt: Text("#tag"))
                    TextField("Notes", text: $edit.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    CalendarPicker(
                        title: "Calendar",
                        selection: $edit.calendarIdentifier,
                        calendars: environment.calendar.writableCalendars,
                        fallbackTitle: "Template Default"
                    )
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Saving updates the Calendar event Calendar Time Logger created for this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || isSaving)
            }
            .padding(12)
        }
        .frame(width: 500, height: 680)
    }

    /// Keeps the recorded seconds unless the minute was changed, so choosing
    /// 11:00 stores 11:00:00 instead of 11:00 plus the old hidden seconds.
    private func minuteBinding(_ keyPath: WritableKeyPath<SessionEdit, Date>) -> Binding<Date> {
        Binding(
            get: { edit[keyPath: keyPath] },
            set: { edit[keyPath: keyPath] = MinuteEditing.pickedTime(original: edit[keyPath: keyPath], picked: $0) }
        )
    }

    private var overlaps: [WorkSession] {
        guard edit.endedAt > edit.startedAt else { return [] }
        return environment.sessions.overlappingWorkLogs(excluding: session, start: edit.startedAt, end: edit.endedAt)
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var overlapMessage: String {
        let items = overlaps.prefix(2).map { other in
            "\(other.templateName) (\(other.startedAt.shortTime) – \((other.endedAt ?? other.startedAt).shortTime))"
        }
        let extra = overlaps.count > 2 ? " and \(overlaps.count - 2) more" : ""
        return "These times overlap \(items.joined(separator: ", "))\(extra). You can still save."
    }

    private func save() {
        var final = edit
        final.tags = TagParsing.parse(tagsText)
        isSaving = true
        Task {
            do {
                let outcome = try await environment.sessions.edit(session, with: final)
                isSaving = false
                if case .failed(let error) = outcome {
                    message = "Saved. \(error.errorDescription ?? "Calendar wasn’t updated.")"
                } else {
                    onClose()
                }
            } catch {
                isSaving = false
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
