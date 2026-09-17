import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Calendar access, default and per-template calendars, and sync issues.
struct CalendarView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            CalendarAccessSection()
            CalendarDefaultsSection()
            CalendarEventTimesSection()
            if environment.calendar.authorization == .fullAccess {
                TemplateCalendarsSection()
                AvailableCalendarsSection()
            }
            SyncIssuesSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
        .onAppear { environment.calendar.refresh() }
    }
}

struct CalendarAccessSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let status = environment.calendar.authorization
        Section {
            LabeledContent("Access") {
                Label(status.displayName, systemImage: status == .fullAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(status == .fullAccess ? .green : .orange)
            }
            switch status {
            case .notDetermined:
                Text("Calendar Time Logger adds each finished session to Apple Calendar. It asks for access the first time you finish work, or you can connect now.")
                    .foregroundStyle(.secondary)
                Button("Connect Apple Calendar") {
                    Task { await environment.calendar.requestAccess() }
                }
            case .denied, .writeOnly:
                Text(status == .writeOnly
                     ? "“Add Events Only” access can’t list calendars or update events the app created. Allow Full Access to use Calendar sync."
                     : "Calendar access is off. Your work is still recorded in Work Logs; it just won’t appear in Calendar.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security Settings") { environment.openCalendarPrivacySettings() }
            case .restricted:
                Text("Calendar access is restricted on this Mac, for example by a device management profile.")
                    .foregroundStyle(.secondary)
            case .fullAccess:
                EmptyView()
            }
        } header: {
            Text("Apple Calendar")
        }
    }
}

struct CalendarDefaultsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Section {
            Toggle("Add finished sessions to Calendar", isOn: $settings.calendarSyncEnabled)
            CalendarPicker(
                title: "Default calendar",
                selection: $settings.defaultCalendarIdentifier,
                calendars: environment.calendar.writableCalendars,
                fallbackTitle: "System Default (\(environment.calendar.systemDefaultCalendar?.title ?? "None"))"
            )
            .disabled(environment.calendar.authorization != .fullAccess)
            Toggle("Include session notes in events", isOn: $settings.includesNotesInEvents)
            Toggle("Include tags in events", isOn: $settings.includesTagsInEvents)
        } header: {
            Text("Sync")
        } footer: {
            Text("Events are created only when you finish work, and span the real start and finish times. Templates can use a different calendar, and each work log can override it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// How session times are written to Calendar events (ADR-026). Work Logs
/// always keep the exact recorded times, whatever is chosen here.
struct CalendarEventTimesSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmsUpdate = false
    @State private var isUpdating = false
    @State private var result: String?

    var body: some View {
        @Bindable var settings = environment.settings
        Section {
            Picker("Calendar event boundaries", selection: $settings.calendarEventTiming) {
                ForEach(CalendarEventTiming.allCases) { timing in
                    Text(timing.title).tag(timing)
                }
            }
            .accessibilityIdentifier("calendar-event-timing")
            Text(settings.calendarEventTiming.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(isUpdating ? "Updating Events…" : "Update Existing Events…") { confirmsUpdate = true }
                    .disabled(isUpdating || !canUpdate)
                    .help(canUpdate ? "Apply this choice to events Calendar Time Logger already created"
                                    : "Needs Calendar sync turned on and full Calendar access")
                if let result {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Event Times")
        } footer: {
            Text("Controls how sessions that end and start at the same time are shown in Calendar. Exact session times are always preserved in Work Logs, Analytics, and exports. New and edited events use this choice; existing events change only when you update them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Update existing Calendar events?", isPresented: $confirmsUpdate) {
            Button("Update Events") { update() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Events Calendar Time Logger created are given times that match “\(environment.settings.calendarEventTiming.title)”. Only its own events are changed, and only when their times differ. Work logs aren’t changed, and deleted events aren’t recreated.")
        }
    }

    private var canUpdate: Bool {
        environment.settings.calendarSyncEnabled && environment.calendar.authorization == .fullAccess
    }

    private func update() {
        isUpdating = true
        result = nil
        Task {
            let sessions = (try? environment.persistence.completedSessions()) ?? []
            let outcome = await environment.calendar.applyEventTimingToExistingEvents(sessions)
            isUpdating = false
            result = switch (outcome.updated, outcome.failed) {
            case (0, 0): "All events already match."
            case (let updated, 0): updated == 1 ? "Updated 1 event." : "Updated \(updated) events."
            case (let updated, let failed): "Updated \(updated); \(failed) couldn’t be updated. See Sync Issues."
            }
        }
    }
}

private struct TemplateCalendarsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]

    var body: some View {
        Section("Templates") {
            if templates.isEmpty {
                Text("No templates yet.").foregroundStyle(.secondary)
            }
            ForEach(templates) { template in
                LabeledContent {
                CalendarPicker(
                    title: template.name,
                    selection: Binding(
                        get: { template.calendarIdentifier },
                        set: { newValue in
                            var draft = template.draft
                            draft.calendarIdentifier = newValue
                            environment.perform { try environment.persistence.updateTemplate(template, with: draft) }
                        }
                    ),
                    calendars: environment.calendar.writableCalendars,
                    fallbackTitle: "Default"
                )
                .labelsHidden()
                .fixedSize()
                } label: {
                    TemplateLabel(name: template.name, icon: template.symbolName, color: template.color, iconSize: 22)
                }
            }
        }
    }
}

private struct AvailableCalendarsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Section("Available Calendars") {
            ForEach(environment.calendar.availableCalendars) { calendar in
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(calendar.color?.color ?? .secondary)
                        .accessibilityHidden(true)
                    Text(calendar.title)
                    Text(calendar.sourceTitle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !calendar.allowsModifications {
                        Label("Read-only", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct SyncIssuesSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }, sort: \WorkSession.startedAt, order: .reverse)
    private var sessions: [WorkSession]
    @State private var isRetrying = false

    var body: some View {
        let issues = sessions.filter { $0.calendarSyncStatus.needsAttention }
        Section {
            if issues.isEmpty {
                Label("All finished sessions are up to date.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(issues) { session in
                    HStack(alignment: .top) {
                        TemplateIconView(icon: session.templateSymbolName, color: session.templateColor, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(session.templateName) · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            if let message = session.calendarSyncMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SyncStatusLabel(status: session.calendarSyncStatus, compact: true)
                        Button("Show") { environment.showWorkLog(session.id, openWindow: openWindow) }
                    }
                }
                Button(isRetrying ? "Retrying…" : "Retry All") {
                    isRetrying = true
                    Task {
                        await environment.calendar.requestAccess()
                        await environment.sessions.retryAllCalendarSyncs()
                        isRetrying = false
                    }
                }
                .disabled(isRetrying)
            }
        } header: {
            Text("Sync Issues")
        } footer: {
            Text("Sessions are always saved first. Calendar Time Logger only updates or removes events it created.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
