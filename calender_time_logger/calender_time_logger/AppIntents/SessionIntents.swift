import AppIntents
import CalendarTimeLoggerKit
import Foundation

/// A template exposed to Shortcuts.
struct TemplateEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Work Template")
    static let defaultQuery = TemplateEntityQuery()

    let id: UUID
    let name: String
    /// SF Symbol name.
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: symbolName))
    }
}

struct TemplateEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TemplateEntity] {
        try allTemplates().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TemplateEntity] {
        try allTemplates()
    }

    @MainActor
    private func allTemplates() throws -> [TemplateEntity] {
        try AppEnvironment.shared.persistence.templates().map {
            TemplateEntity(id: $0.id, name: $0.name, symbolName: $0.symbolName)
        }
    }
}

enum SessionIntentError: Error, CustomLocalizedStringResourceConvertible {
    case templateNotFound
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .templateNotFound: "That template no longer exists."
        case .failed(let message): "\(message)"
        }
    }
}

struct StartWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Work"
    static let description = IntentDescription("Starts a live work session from a template.")

    @Parameter(title: "Template")
    var template: TemplateEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared
        guard let model = environment.persistence.template(id: template.id) else {
            throw SessionIntentError.templateNotFound
        }
        do {
            try environment.sessions.start(template: model)
        } catch {
            throw SessionIntentError.failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        environment.updateClock()
        return .result(dialog: "Started \(model.name).")
    }
}

struct PauseResumeWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Work"
    static let description = IntentDescription("Pauses the running session, or resumes it if paused.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared
        guard let session = environment.sessions.activeSession else {
            throw SessionIntentError.failed(SessionError.noActiveSession.errorDescription ?? "")
        }
        let wasPaused = session.state == .paused
        do {
            if wasPaused { try environment.sessions.resume() } else { try environment.sessions.pause() }
        } catch {
            throw SessionIntentError.failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        environment.updateClock()
        return .result(dialog: wasPaused ? "Resumed \(session.templateName)." : "Paused \(session.templateName).")
    }
}

struct FinishWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Work"
    static let description = IntentDescription("Finishes the current session, saves it to Work Logs, and adds it to Calendar.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = AppEnvironment.shared
        do {
            let completion = try await environment.sessions.finish()
            environment.updateClock()
            let log = completion.log
            let calendarText = completion.calendarOutcome?.succeeded == true ? " Added to Calendar." : ""
            return .result(dialog: "Finished \(log.templateName): \(DurationFormatting.short(log.activeDuration)) of active work.\(calendarText)")
        } catch {
            throw SessionIntentError.failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

struct CalendarTimeLoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartWorkIntent(), phrases: ["Start work in \(.applicationName)"],
                    shortTitle: "Start Work", systemImageName: "play.fill")
        AppShortcut(intent: PauseResumeWorkIntent(), phrases: ["Pause work in \(.applicationName)"],
                    shortTitle: "Pause or Resume", systemImageName: "pause.fill")
        AppShortcut(intent: FinishWorkIntent(), phrases: ["Finish work in \(.applicationName)"],
                    shortTitle: "Finish Work", systemImageName: "checkmark.circle")
    }
}
