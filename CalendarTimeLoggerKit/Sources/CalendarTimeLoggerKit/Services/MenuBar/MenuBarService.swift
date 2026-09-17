import Foundation

/// Builds the menu bar presentation for the current session using the live
/// configuration of its template.
@MainActor
public final class MenuBarService {
    private let persistence: PersistenceService
    let settings: SettingsStore

    public init(persistence: PersistenceService, settings: SettingsStore) {
        self.persistence = persistence
        self.settings = settings
    }

    public func snapshot(for session: WorkSession?, now: Date) -> MenuBarSessionSnapshot? {
        guard let session, session.state.isOpen else { return nil }
        // A deleted template falls back to its snapshot identity and default styling.
        let template = persistence.template(id: session.templateID)
        return MenuBarSessionSnapshot(
            templateName: template?.name ?? session.templateName,
            templateIcon: template?.symbolName ?? session.templateSymbolName,
            state: session.state,
            activeDuration: session.activeDuration(at: now),
            configuration: template?.menuBarConfiguration ?? .default
        )
    }

    public func presentation(for session: WorkSession?, now: Date) -> MenuBarPresentation {
        MenuBarFormatter.presentation(for: snapshot(for: session, now: now), showsSeconds: settings.menuBarShowsSeconds)
    }
}
