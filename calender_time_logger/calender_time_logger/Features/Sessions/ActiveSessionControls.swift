import CalendarTimeLoggerKit
import SwiftUI

/// The live timer text, derived from session timestamps.
struct LiveDurationText: View {
    let session: WorkSession
    let now: Date
    var font: Font = .system(size: 44, weight: .semibold, design: .rounded)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let active = session.activeDuration(at: now)
        Text(DurationFormatting.clock(active))
            .font(font)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .foregroundStyle(session.state == .paused ? .secondary : .primary)
            .accessibilityLabel(session.state == .paused ? "Active time, paused" : "Active time")
            .accessibilityValue(DurationFormatting.spoken(active, includesSeconds: false))
    }
}

/// Pause/Resume and Finish Work buttons.
struct SessionPrimaryButtons: View {
    @Environment(AppEnvironment.self) private var environment
    let session: WorkSession
    var controlSize: ControlSize = .large

    var body: some View {
        HStack(spacing: 12) {
            if session.state == .paused {
                Button {
                    environment.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Continues timing \(session.templateName)")
            } else {
                Button {
                    environment.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Pauses timing without ending the session")
            }

            Button {
                environment.finish()
            } label: {
                Label("Finish Work", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Ends the session, saves it to Work Logs, and adds it to Calendar")
        }
        .controlSize(controlSize)
    }
}

/// A single-line field that appends a timestamped note to the active session.
struct AddNoteField: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var text = ""
    @FocusState private var isFocused: Bool
    var autofocus = false
    var prompt = "Add a note…"
    /// Changing this value moves keyboard focus to the field.
    var focusRequest = 0

    var body: some View {
        HStack(spacing: 8) {
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isFocused)
                .onSubmit(submit)
                .accessibilityLabel("Note")
            Button("Add", action: submit)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { if autofocus { isFocused = true } }
        .onChange(of: focusRequest) { isFocused = true }
    }

    private func submit() {
        environment.appendNote(text)
        text = ""
    }
}

/// A prominent Start Work button with an attached template menu, as in the
/// Dashboard's Ready to work card.
///
/// The button opens the Start Work sheet, where the task priority can be
/// reviewed before the timer starts; the menu starts a template straight away
/// with that template's own priority.
struct StartWorkSplitButton: View {
    @Environment(AppEnvironment.self) private var environment
    let templates: [WorkTemplate]

    var body: some View {
        let primary = environment.preferredTemplate(from: templates)
        let enabled = !templates.isEmpty && environment.sessions.canRecordWork && environment.sessions.activeSession == nil
        HStack(spacing: 0) {
            Button {
                environment.requestStartSession()
            } label: {
                Label("Start Work", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.leading, 18)
                    .padding(.trailing, 12)
                    .frame(height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(primary.map { "Start \($0.name), with a look at its task priority first" } ?? "Choose a template")
            .accessibilityHint("Shows the template and task priority before the timer starts")

            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(width: 1, height: 24)
                .accessibilityHidden(true)

            Menu {
                ForEach(templates) { template in
                    Button { environment.start(template) } label: {
                        Label(template.name, systemImage: template.symbolName)
                    }
                }
                Divider()
                Button { environment.requestQuickTask() } label: {
                    Label("Quick New Task…", systemImage: PrioritySymbols.quickTask)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.callout.weight(.bold))
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose a template to start")
        }
        .foregroundStyle(.white)
        .background(Color.accentColor, in: .rect(cornerRadius: 10))
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }
}

/// Opens the Start Work sheet, with a menu that starts any template directly.
struct StartWorkMenu: View {
    @Environment(AppEnvironment.self) private var environment
    let templates: [WorkTemplate]
    var title = "Start Work"

    var body: some View {
        Menu {
            Button { environment.requestStartSession() } label: {
                Label("Start Work…", systemImage: "play.fill")
            }
            .disabled(templates.isEmpty)
            Button { environment.requestQuickTask() } label: {
                Label("Quick New Task…", systemImage: PrioritySymbols.quickTask)
            }
            if !templates.isEmpty {
                Divider()
                Section("Start a Template") {
                    ForEach(templates) { template in
                        Button { environment.start(template) } label: {
                            Label(template.name, systemImage: template.symbolName)
                        }
                    }
                }
            }
        } label: {
            Label(title, systemImage: "play.fill")
        } primaryAction: {
            if templates.isEmpty {
                environment.requestQuickTask()
            } else {
                environment.requestStartSession()
            }
        }
        .help("Start work. Click the arrow to start a template directly.")
        .accessibilityHint("Shows the template and task priority before the timer starts")
        .disabled(!environment.sessions.canRecordWork)
    }
}
