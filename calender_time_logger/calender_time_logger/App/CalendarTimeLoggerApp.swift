import AppKit
import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

@main
struct CalendarTimeLoggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        // Before any service opens the database or the CTL item is created.
        SingleInstance.deferToRunningInstanceIfNeeded()
        _environment = State(initialValue: AppEnvironment.shared)
    }

    var body: some Scene {
        Window("Calendar Time Logger", id: WindowID.main) {
            RootView()
                .environment(environment)
                .appAppearance(environment.settings)
        }
        .modelContainer(environment.persistence.container)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(environment.settings.opensMainWindowAtLaunch ? .presented : .suppressed)
        .commands {
            SessionCommands(environment: environment)
            NavigationCommands(environment: environment)
            ExportCommands(environment: environment)
        }

        // The permanent CTL item. A single scene owned by this process, so it
        // can't be duplicated and macOS removes it when the app quits.
        MenuBarExtra(isInserted: Binding(
            get: { environment.menuBar.isItemInserted },
            set: { environment.settings.showsMenuBarItem = $0 }
        )) {
            MenuBarContentView()
                .environment(environment)
                .modelContainer(environment.persistence.container)
                .appAppearance(environment.settings)
        } label: {
            MenuBarLabel(environment: environment)
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        Window("Menu Bar Preview", id: "demo-menu") {
            MenuBarContentView()
                .environment(environment)
                .modelContainer(environment.persistence.container)
                .appAppearance(environment.settings)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #endif

        Settings {
            SettingsView()
                .environment(environment)
                .modelContainer(environment.persistence.container)
                .appAppearance(environment.settings)
        }
    }
}

/// Shows the main window once at launch when “Show the main window when
/// Calendar Time Logger opens” is on.
@MainActor
enum LaunchWindowPresenter {
    private static var didRun = false

    static func presentIfNeeded(environment: AppEnvironment, openWindow: OpenWindowAction) async {
        guard !didRun else { return }
        didRun = true
        guard environment.settings.opensMainWindowAtLaunch else { return }
        // Give scene restoration a moment to reopen windows first.
        try? await Task.sleep(for: .milliseconds(600))
        let hasMainWindow = NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }
        if !hasMainWindow {
            openWindow(id: WindowID.main)
        }
    }
}

/// App lifecycle hooks SwiftUI doesn't expose.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the main window keeps the app, and its CTL item, running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Keeps a single copy of Calendar Time Logger running.
enum SingleInstance {
    /// A second copy would add a second CTL item and share the database, so it
    /// activates the copy already running and quits.
    static func deferToRunningInstanceIfNeeded() {
        #if DEBUG
        // Demo mode uses its own in-memory store and may run beside the real app.
        guard DemoMode.current == nil else { return }
        #endif
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let instances = running.map { RunningAppInstance(processIdentifier: $0.processIdentifier, launchDate: $0.launchDate) }
        let me = RunningAppInstance(processIdentifier: current.processIdentifier, launchDate: current.launchDate)
        guard let existing = AppInstancePolicy.instanceToDefer(to: me, among: instances),
              let app = running.first(where: { $0.processIdentifier == existing.processIdentifier }) else { return }
        app.activate()
        exit(0)
    }
}
