import AppKit
import CalendarTimeLoggerKit
import Observation
import SwiftUI

enum WindowID {
    static let main = "main"
}

/// A user-facing error built from any `LocalizedError`.
struct PresentableError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    init(_ error: Error, title: String? = nil) {
        let localized = error as? LocalizedError
        self.title = title ?? localized?.errorDescription ?? "Something went wrong"
        self.message = [
            title == nil ? nil : localized?.errorDescription,
            localized?.failureReason,
            localized?.recoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}

/// Composition root: creates services once and exposes UI-facing actions that
/// present errors instead of throwing.
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: SettingsStore
    let persistence: PersistenceService
    let calendar: CalendarService
    let notifications: NotificationService
    let sessions: SessionService
    let menuBar: MenuBarService
    let clock: SessionClock
    let exporter: WorkLogExportService
    let workLogFilters = WorkLogFilterState()

    var selectedSection: AppSection = .dashboard
    var selectedWorkLogID: UUID?
    var selectedTemplateID: UUID?
    var presentedError: PresentableError?
    /// Shown after the Mac slept and the session was paused automatically.
    var pausedForSleepNotice = false
    var isExportPresented = false
    /// Start Work with a review of the task priority before the timer starts.
    var isStartSessionPresented = false
    /// Quick New Task: name the work and classify it without a template.
    var isQuickTaskPresented = false
    /// Changing the priority of the session in progress.
    var isChangePriorityPresented = false
    /// Manage Categories, from the Templates screen.
    var isManageCategoriesPresented = false
    var isNewTemplatePresented = false
    /// Preselects Current Filter when export starts from a filtered Work Logs list.
    var exportPrefersCurrentFilter = false
    var exportNotice: ExportNotice?

    struct ExportNotice: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let sessionCount: Int
    }

    @ObservationIgnored private let calendarProvider: any CalendarProviding
    @ObservationIgnored private var heartbeatTimer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        var settings = SettingsStore()
        var persistence: PersistenceService
        #if DEBUG
        if let demo = DemoMode.current {
            settings = demo.makeSettings()
            persistence = demo.makePersistence()
        } else {
            persistence = Self.openPersistentStore()
        }
        #else
        persistence = Self.openPersistentStore()
        #endif

        let provider: any CalendarProviding
        #if DEBUG
        // Demo mode never reads the real calendar list, so screenshots can't show it.
        provider = DemoMode.current.map { _ in DemoCalendarProvider() } ?? EventKitCalendarProvider()
        #else
        provider = EventKitCalendarProvider()
        #endif
        let calendar = CalendarService(provider: provider, persistence: persistence) { settings.calendarConfiguration }
        let notifications = NotificationService(scheduler: UserNotificationScheduler()) { settings.notificationPreferences }

        self.settings = settings
        self.persistence = persistence
        self.calendarProvider = provider
        self.calendar = calendar
        self.notifications = notifications
        self.sessions = SessionService(persistence: persistence, calendarService: calendar, notificationService: notifications)
        self.menuBar = MenuBarService(persistence: persistence, settings: settings)
        self.clock = SessionClock()
        self.exporter = WorkLogExportService(persistence: persistence, calendarName: { calendar.calendar(withIdentifier: $0)?.title })

        #if DEBUG
        DemoMode.current?.configure(self)
        #endif
        (provider as? EventKitCalendarProvider)?.onStoreChanged = { [weak self] in self?.calendarDatabaseChanged() }
        updateClock()
        startHeartbeat()
        observeWorkspace()
        Task { await notifications.refreshAuthorization() }
        reconcileCalendarEvents()
    }

    /// Opens the on-disk store, seeds default templates on first launch, and
    /// converts 1.0 emoji icons to SF Symbols.
    private static func openPersistentStore() -> PersistenceService {
        let persistence = PersistenceService.makeDefault()
        try? persistence.seedDefaultTemplatesIfNeeded(defaults: .standard)
        _ = try? persistence.migrateLegacyIconsIfNeeded(defaults: .standard)
        return persistence
    }

    // MARK: Session actions

    /// Starts a template immediately, using the template's own priority.
    func start(_ template: WorkTemplate) {
        perform { try sessions.start(template: template) }
    }

    /// Starts a template with the priority and category the user chose for this
    /// session. `nil` category uses the template's own.
    func start(_ template: WorkTemplate, priority: TaskPriority, category: String? = nil) {
        perform { try sessions.start(template: template, priority: priority, category: category) }
    }

    func startQuickTask(_ draft: QuickTaskDraft) {
        perform { try sessions.startQuickTask(draft) }
    }

    /// Changes the priority of the session in progress.
    func updateTaskPriority(_ priority: TaskPriority) {
        perform { try sessions.updateTaskPriority(priority) }
    }

    /// Changes the category of the session in progress. The template is not edited.
    func updateCategory(_ category: String) {
        perform { try sessions.updateCategory(category) }
    }

    func requestStartSession() {
        guard sessions.activeSession == nil else { return }
        isStartSessionPresented = true
    }

    func requestQuickTask() {
        guard sessions.activeSession == nil else { return }
        isQuickTaskPresented = true
    }

    func pause() { perform { try sessions.pause() } }

    func resume() {
        pausedForSleepNotice = false
        perform { try sessions.resume() }
    }

    func togglePause() {
        guard let session = sessions.activeSession else { return }
        session.state == .paused ? resume() : pause()
    }

    func finish() {
        pausedForSleepNotice = false
        Task {
            do {
                try await sessions.finish()
            } catch {
                presentedError = PresentableError(error, title: "Couldn’t finish work")
            }
            updateClock()
        }
        // Stop the live timer immediately; the completion sheet takes over.
        clock.tick()
    }

    func cancel() {
        pausedForSleepNotice = false
        perform { try sessions.cancel() }
    }

    func changeTemplate(to template: WorkTemplate) {
        perform { try sessions.changeTemplate(to: template) }
    }

    func appendNote(_ text: String) {
        perform { try sessions.appendNote(text) }
    }

    func resolveRecovery(_ choice: RecoveryChoice) {
        Task {
            do {
                try await sessions.resolveRecovery(choice)
            } catch {
                presentedError = PresentableError(error, title: "Couldn’t recover the session")
            }
            updateClock()
        }
    }

    /// Runs a throwing action, presents any error, and refreshes the timer.
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            presentedError = PresentableError(error)
        }
        updateClock()
    }

    // MARK: Templates

    /// The template the Start Work button starts: the default template from
    /// Settings, otherwise the most recently used one, otherwise the first.
    func preferredTemplate(from templates: [WorkTemplate]) -> WorkTemplate? {
        if let id = settings.defaultTemplateID, let template = templates.first(where: { $0.id == id }) {
            return template
        }
        let sessions = (try? persistence.completedSessions()) ?? []
        return Self.templatesByRecentUse(templates, sessions: sessions).first
    }

    /// Templates ordered by most recent use, then by template order.
    static func templatesByRecentUse(_ templates: [WorkTemplate], sessions: [WorkSession]) -> [WorkTemplate] {
        var lastUsed: [UUID: Date] = [:]
        for session in sessions {
            guard let id = session.templateID else { continue }
            lastUsed[id] = max(lastUsed[id] ?? .distantPast, session.startedAt)
        }
        return templates.enumerated()
            .sorted { lhs, rhs in
                switch (lastUsed[lhs.element.id], lastUsed[rhs.element.id]) {
                case let (l?, r?): l > r
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    // MARK: Export

    func requestExport() {
        exportPrefersCurrentFilter = selectedSection == .workLogs
        isExportPresented = true
    }

    func exportFinished(url: URL, sessionCount: Int) {
        exportNotice = ExportNotice(url: url, sessionCount: sessionCount)
        if settings.exportRevealsInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: Navigation

    func show(_ section: AppSection, openWindow: OpenWindowAction) {
        selectedSection = section
        openMainWindow(openWindow)
    }

    func showWorkLog(_ id: UUID, openWindow: OpenWindowAction) {
        selectedWorkLogID = id
        show(.workLogs, openWindow: openWindow)
    }

    func openMainWindow(_ openWindow: OpenWindowAction) {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }

    func handle(url: URL) {
        guard let sessionID = CalendarOwnership.sessionID(from: url) else { return }
        selectedWorkLogID = sessionID
        selectedSection = .workLogs
    }

    func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Calendar

    func reconcileCalendarEvents() {
        #if DEBUG
        // Demo data has no real events; never compare it with the user's calendars.
        guard DemoMode.current == nil else { return }
        #endif
        guard let sessions = try? persistence.completedSessions() else { return }
        calendar.reconcile(Array(sessions.prefix(500)))
    }

    private func calendarDatabaseChanged() {
        calendar.refresh()
        reconcileCalendarEvents()
    }

    // MARK: System integration

    /// Runs the 1-second UI clock only while a session is open.
    func updateClock() {
        if sessions.activeSession?.state == .active {
            clock.start()
        } else {
            clock.stop()
        }
    }

    private func startHeartbeat() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.recordHeartbeat() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sessions.recordHeartbeat()
                if self.settings.pausesOnSleep, self.sessions.pauseForSystemSleep() {
                    self.pausedForSleepNotice = true
                    self.updateClock()
                }
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.clock.tick()
                self.calendar.refresh()
            }
        })
    }
}
