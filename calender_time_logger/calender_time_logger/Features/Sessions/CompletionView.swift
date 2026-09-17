import CalendarTimeLoggerKit
import SwiftUI

/// The “Work Completed” confirmation shown after Finish Work.
struct CompletionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completionID: UUID

    @State private var notes = ""
    @State private var didLoadNotes = false
    @State private var appeared = false

    var body: some View {
        let completion = environment.sessions.lastCompletion
        VStack(spacing: 16) {
            if let completion {
                content(completion)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            appeared = true
            guard !didLoadNotes, let session = environment.persistence.session(id: completionID) else { return }
            notes = session.notes
            didLoadNotes = true
        }
    }

    @ViewBuilder
    private func content(_ completion: SessionCompletion) -> some View {
        let log = completion.log
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                // A single, subtle bounce; Reduce Motion shows the symbol without it.
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : appeared)
                .accessibilityHidden(true)
            Text("Work Completed")
                .font(.title.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            TemplateLabel(name: log.templateName, icon: log.templateIcon, color: log.templateColor, iconSize: 30)
                .font(.title3.weight(.medium))
            PriorityChips(priority: log.taskPriority, showsNeither: true)
        }

        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("Time", "\(log.startedAt.shortTime) – \(log.endedAt.shortTime)")
            row("Duration", DurationFormatting.short(log.wallClockDuration))
            row("Active Work", DurationFormatting.short(log.activeDuration), emphasized: true)
            row("Paused", log.pausedDuration < 1 ? "0m" : DurationFormatting.short(log.pausedDuration))
            row("Category", log.category)
            row("Task Priority", log.taskPriority.quadrant.title)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)

        CompletionCalendarStatus(completion: completion, completionID: completionID)

        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.headline)
            TextEditor(text: $notes)
                .font(.body)
                .frame(height: 76)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: Metrics.controlCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityLabel("Session notes")
        }

        HStack {
            Button("View in Work Logs") {
                saveNotesIfNeeded()
                environment.selectedWorkLogID = log.id
                environment.selectedSection = .workLogs
                close()
            }
            .controlSize(.large)
            Spacer()
            Button {
                saveNotesIfNeeded()
                close()
            } label: {
                Text("Done").frame(minWidth: 90)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func row(_ title: String, _ value: String, emphasized: Bool = false) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value).fontWeight(emphasized ? .semibold : .regular)
                .gridColumnAlignment(.leading)
        }
    }

    /// Notes added here update the saved session and, if present, its event.
    private func saveNotesIfNeeded() {
        guard let session = environment.persistence.session(id: completionID), session.notes != notes else { return }
        var edit = SessionEdit(session: session)
        edit.notes = notes
        Task {
            do {
                try await environment.sessions.edit(session, with: edit)
            } catch {
                environment.presentedError = PresentableError(error, title: "Couldn’t save notes")
            }
        }
    }

    private func close() {
        environment.sessions.lastCompletion = nil
        dismiss()
    }
}

/// The Calendar result of a completion, with its follow-up actions.
struct CompletionCalendarStatus: View {
    @Environment(AppEnvironment.self) private var environment
    let completion: SessionCompletion
    var completionID: UUID?
    var compact = false
    @State private var isRetrying = false

    var body: some View {
        switch completion.calendarOutcome {
        case nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Adding to Calendar…")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .created, .updated:
            HStack {
                Label("Calendar event created\(completion.calendarName.map { " in \($0)" } ?? "").", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.green)
                if !compact {
                    Spacer()
                    Button("View in Calendar") { environment.openCalendarApp() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .skipped:
            Label("Calendar sync is off, so no event was created.", systemImage: "calendar")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 6) {
                Label(error.errorDescription ?? "Calendar sync failed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if !compact {
                    Text("Your work is saved in Work Logs. \(error.recoverySuggestion ?? "")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(isRetrying ? "Retrying…" : "Retry") { retry() }
                            .disabled(isRetrying || completionID == nil)
                        if case .accessNotGranted(let status) = error, status != .notDetermined {
                            Button("Open Privacy Settings") { environment.openCalendarPrivacySettings() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func retry() {
        guard let completionID, let session = environment.persistence.session(id: completionID) else { return }
        isRetrying = true
        Task {
            let outcome = await environment.sessions.retryCalendarSync(session)
            environment.sessions.lastCompletion?.calendarOutcome = outcome
            environment.sessions.lastCompletion?.calendarName = environment.calendar.calendar(withIdentifier: session.eventCalendarIdentifier)?.title
            isRetrying = false
        }
    }
}

/// Shown on the Dashboard when an open session is found at launch.
struct RecoveryCard: View {
    @Environment(AppEnvironment.self) private var environment
    let session: WorkSession

    var body: some View {
        let lastSeen = session.lastHeartbeatAt.flatMap { session.state == .active && Date().timeIntervalSince($0) > 5 * 60 ? $0 : nil }
        VStack(alignment: .leading, spacing: 14) {
            Label("Active Session Detected", systemImage: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                TemplateIconView(icon: session.templateSymbolName, color: session.templateColor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.templateName).font(.headline)
                    Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.state == .paused
                     ? "This session was paused when Calendar Time Logger closed."
                     : "The timer kept running while Calendar Time Logger was closed.")
                if let lastSeen {
                    Text("Calendar Time Logger was last running at \(lastSeen.shortTime).")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Resume Session") { environment.resolveRecovery(.resume) }
                    .buttonStyle(.borderedProminent)
                Button("Finish Work") { environment.resolveRecovery(.finishNow) }
                    .buttonStyle(.bordered)
                if let lastSeen {
                    Button("Finish at \(lastSeen.shortTime)") { environment.resolveRecovery(.finishAtLastSeen) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Cancel Session", role: .destructive) { environment.resolveRecovery(.cancel) }
                    .buttonStyle(.link)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
