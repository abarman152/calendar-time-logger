import AppKit
import CalendarTimeLoggerKit
import SwiftUI

/// The Session menu: keyboard access to the whole session lifecycle.
struct SessionCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandMenu("Session") {
            SessionCommandsContent(environment: environment)
        }
    }
}

private struct SessionCommandsContent: View {
    let environment: AppEnvironment

    var body: some View {
        let session = environment.sessions.activeSession
        let templates = (try? environment.persistence.templates()) ?? []

        Button("Start Work…") { environment.requestStartSession() }
            .keyboardShortcut("s", modifiers: [.option, .command])
            .disabled(session != nil || templates.isEmpty || !environment.sessions.canRecordWork)

        Button("Quick New Task…") { environment.requestQuickTask() }
            .keyboardShortcut("n", modifiers: [.option, .command])
            .disabled(session != nil || !environment.sessions.canRecordWork)

        Menu("Start Template") {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                if index < 9 {
                    Button { environment.start(template) } label: { Label(template.name, systemImage: template.symbolName) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.control, .command])
                } else {
                    Button { environment.start(template) } label: { Label(template.name, systemImage: template.symbolName) }
                }
            }
        }
        .disabled(session != nil || templates.isEmpty || !environment.sessions.canRecordWork)

        if let session, session.state == .paused {
            Button("Resume") { environment.resume() }
                .keyboardShortcut("p", modifiers: [.option, .command])
        } else {
            Button("Pause") { environment.pause() }
                .keyboardShortcut("p", modifiers: [.option, .command])
                .disabled(session == nil)
        }

        Button("Finish Work") { environment.finish() }
            .keyboardShortcut("f", modifiers: [.option, .command])
            .disabled(session == nil)

        Divider()

        Button("Change Category and Priority…") { environment.isChangePriorityPresented = true }
            .disabled(session == nil)

        Menu("Change Template") {
            ForEach(templates) { template in
                Button { environment.changeTemplate(to: template) } label: { Label(template.name, systemImage: template.symbolName) }
                    .disabled(template.id == session?.templateID)
            }
        }
        .disabled(session == nil)

        Button("Cancel Session…") { SessionCancelConfirmation.run(environment: environment) }
            .disabled(session == nil)
    }
}

/// ⌘1–⌘5 switch between the main window's work sections.
struct NavigationCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(Array(AppSection.primary.enumerated()), id: \.element) { index, section in
                Button(section.title) { environment.selectedSection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }
    }
}

/// File › Export Work Logs… (⇧⌘E).
struct ExportCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export Work Logs…") { environment.requestExport() }
                .keyboardShortcut("e", modifiers: [.shift, .command])
        }
    }
}

/// Confirms Cancel Session from the Session menu, like the Dashboard and the
/// menu bar do. A menu command can't present a SwiftUI dialog when the main
/// window is closed, so this uses an alert. Keep Working is the default button,
/// so pressing Return never discards the session.
@MainActor
enum SessionCancelConfirmation {
    static func run(environment: AppEnvironment) {
        guard let session = environment.sessions.activeSession else { return }
        let alert = NSAlert()
        alert.messageText = "Cancel this session?"
        alert.informativeText = "The timer stops and “\(session.templateName)” won’t appear in Work Logs, analytics, or Calendar."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Working")
        let cancel = alert.addButton(withTitle: "Cancel Session")
        cancel.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        // The session may have been finished elsewhere while the alert was up.
        guard environment.sessions.activeSession?.id == session.id else { return }
        environment.cancel()
    }
}
