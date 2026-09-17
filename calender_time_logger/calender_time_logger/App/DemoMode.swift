#if DEBUG
import CalendarTimeLoggerKit
import AppKit
import Foundation
import SwiftData
import SwiftUI

/// DEBUG-only demo mode for manual QA and screenshots.
///
/// Launch with `-demo` to use an in-memory store, a separate defaults suite,
/// Calendar sync turned off, sample calendars, and sample data. Real user data
/// and calendars are never read or touched. Optional arguments:
/// - `-demoState idle|active|paused|recovery|completion|export|onboarding|quickTask|startSession|priority`
/// - `-demoSection dashboard|templates|workLogs|calendar|analytics|settings|about`
/// - `-demoMenuWindow` shows the menu bar popover content in a regular window
/// - `-demoLegacyIcons` stores 1.0-style emoji icons, then runs the icon migration
/// - `-demoSyncFailure` records one of today's sessions as a failed Calendar sync, to show
///   the Sync Failed states; without it the demo has no Calendar warnings
/// - `-demoExportDirectory <path>` writes an export there without the Save panel,
///   with `-demoExportColumns basic|detailed|priorityAnalysis|everything` choosing the columns
/// - `-demoAppearance system|light|dark` and `-demoWindowSize 1440x900` for screenshots
/// - `-demoAnalyticsRange today|thisWeek|last7|thisMonth|last30` and `-demoExpandCategories`
///   choose what Analytics shows first
/// - `-demoState categories` opens Manage Categories on the Templates screen, and
///   `-demoState newTemplate` the New Template sheet (both with `-demoSection templates`)
/// - `-demoSettingsPane general|menuBar|notifications|appearance|export|calendar|privacy`
///   opens that Settings pane (with `-demoSection settings`)
/// - `-demoPersistentStore` keeps the demo data and settings on disk in the sandbox's
///   temporary directory, so a relaunch can verify that edits and deletes persist.
///   Sample data is written only when that store is new; `-demoResetStore` starts over.
///   Use it with `-demoState idle`, since other states add a session on every launch.
struct DemoMode {
    let state: String
    let section: AppSection
    let showsMenuWindow: Bool
    let usesLegacyIcons: Bool
    let showsSyncFailure: Bool
    let exportDirectory: String?
    let exportColumns: WorkLogColumnSelection
    let windowSize: CGSize?
    let usesPersistentStore: Bool
    let resetsPersistentStore: Bool

    private static let persistentSettingsSuite = "CalendarTimeLogger.demo.persistent"
    private static var persistentStoreURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "CalendarTimeLogger-Demo.store")
    }

    static let current: DemoMode? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-demo") else { return nil }
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        return DemoMode(
            state: value(after: "-demoState") ?? "active",
            section: value(after: "-demoSection").flatMap(AppSection.init) ?? .dashboard,
            showsMenuWindow: arguments.contains("-demoMenuWindow"),
            usesLegacyIcons: arguments.contains("-demoLegacyIcons"),
            showsSyncFailure: arguments.contains("-demoSyncFailure"),
            exportDirectory: value(after: "-demoExportDirectory"),
            exportColumns: value(after: "-demoExportColumns")
                .flatMap { WorkLogExportPreset(rawValue: $0)?.selection } ?? .default,
            windowSize: value(after: "-demoWindowSize").flatMap { text in
                let parts = text.split(separator: "x").compactMap { Double($0) }
                return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
            },
            usesPersistentStore: arguments.contains("-demoPersistentStore"),
            resetsPersistentStore: arguments.contains("-demoResetStore")
        )
    }()

    func makeSettings() -> SettingsStore {
        let suite = usesPersistentStore ? Self.persistentSettingsSuite : "CalendarTimeLogger.demo"
        if !usesPersistentStore || resetsPersistentStore {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        settings.calendarSyncEnabled = false
        settings.notificationsEnabled = false
        settings.hasCompletedOnboarding = state != "onboarding"
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-demoAppearance"), arguments.indices.contains(index + 1),
           let appearance = AppearancePreference(rawValue: arguments[index + 1]) {
            settings.appearance = appearance
        }
        return settings
    }

    func makePersistence() -> PersistenceService {
        if usesPersistentStore { return makePersistentStore() }
        let persistence = try! PersistenceService.inMemory()
        let defaults = UserDefaults(suiteName: "CalendarTimeLogger.demo.seed")!
        defaults.removePersistentDomain(forName: "CalendarTimeLogger.demo.seed")
        try? persistence.seedDefaultTemplatesIfNeeded(defaults: defaults)
        seed(persistence)
        if usesLegacyIcons {
            // Simulate a 1.0 store, then migrate exactly as a real launch does.
            let emoji = ["💻", "📚", "🧪", "✍️", "🎨"]
            for (index, template) in ((try? persistence.templates()) ?? []).enumerated() {
                template.icon = emoji[index % emoji.count]
            }
            for session in (try? persistence.context.fetch(FetchDescriptor<WorkSession>())) ?? [] {
                session.templateIcon = "💻"
            }
            try? persistence.save()
            let result = try? persistence.migrateLegacyIconsIfNeeded(defaults: defaults)
            print("Demo icon migration: \(result.map { "\($0.templates) templates, \($0.sessions) sessions" } ?? "failed")")
        }
        return persistence
    }

    /// The on-disk demo store for relaunch checks. Never the user's store: it
    /// lives in the sandbox's temporary directory under its own name.
    private func makePersistentStore() -> PersistenceService {
        let url = Self.persistentStoreURL
        if resetsPersistentStore {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
            }
        }
        let persistence = try! PersistenceService.open(url: url)
        let defaults = UserDefaults(suiteName: Self.persistentSettingsSuite)!
        if !defaults.bool(forKey: "demo.didSeedPersistentStore") {
            try? persistence.seedDefaultTemplatesIfNeeded(defaults: defaults)
            seed(persistence)
            defaults.set(true, forKey: "demo.didSeedPersistentStore")
        }
        print("Demo persistent store: \(url.path())")
        return persistence
    }

    private func seed(_ persistence: PersistenceService) {
        guard let templates = try? persistence.templates(), templates.count >= 5 else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let context = persistence.context

        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: calendar.date(byAdding: .day, value: -dayOffset, to: today)!)!
        }

        func completed(_ template: WorkTemplate, day: Int, from: (Int, Int), to: (Int, Int), pause: Int = 0,
                       notes: String = "", status: CalendarSyncStatus = .synced, priority: TaskPriority? = nil) {
            let start = at(day, from.0, from.1)
            let end = at(day, to.0, to.1)
            guard end < Date() else { return }
            let session = WorkSession(templateID: template.id, templateName: template.name, templateIcon: template.symbolName,
                                      templateColorHex: template.colorHex, startedAt: start, tags: template.tags, notes: notes,
                                      taskPriority: priority ?? template.taskPriority, category: template.category)
            if pause > 0 {
                let pauseStart = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
                session.pauses = [PauseInterval(start: pauseStart, end: pauseStart.addingTimeInterval(TimeInterval(pause * 60)))]
            }
            session.endedAt = end
            session.state = .completed
            session.calendarSyncStatus = status
            if status == .synced { session.calendarEventIdentifier = "demo-\(session.id)" }
            if status == .failed {
                session.calendarSyncMessage = CalendarSyncError.accessNotGranted(.denied).storedMessage
            }
            context.insert(session)
        }

        func completed(_ template: WorkTemplate, start: Date, minutes: Int, notes: String = "", status: CalendarSyncStatus = .synced) {
            let from = calendar.dateComponents([.hour, .minute], from: start)
            let end = start.addingTimeInterval(TimeInterval(minutes * 60))
            let to = calendar.dateComponents([.hour, .minute], from: end)
            completed(template, day: 0, from: (from.hour!, from.minute!), to: (to.hour!, to.minute!), notes: notes, status: status)
        }

        let engineering = templates[0], study = templates[1], research = templates[2], writing = templates[3], design = templates[4]
        // A spread of task priorities, so every screen has all four combinations.
        engineering.taskPriority = TaskPriority(isUrgent: false, isImportant: true)
        study.taskPriority = TaskPriority(isUrgent: false, isImportant: false)
        research.taskPriority = TaskPriority(isUrgent: false, isImportant: true)
        writing.taskPriority = TaskPriority(isUrgent: true, isImportant: false)
        design.taskPriority = TaskPriority(isUrgent: false, isImportant: false)
        // Today's work is placed shortly before now (never before midnight) so
        // the Dashboard has data whatever time demo mode is launched.
        let todayBase = max(today, Date().addingTimeInterval(-3 * 3600))
        completed(writing, start: todayBase.addingTimeInterval(60), minutes: 5, notes: "Outlined ideas for blog post.")
        completed(research, start: todayBase.addingTimeInterval(8 * 60), minutes: 2,
                  status: showsSyncFailure ? .failed : .synced)
        // Thirty consecutive days of history (today plus the 29 before it), with
        // lighter weekends, so every date range and category has data.
        let notesByDay = ["Reviewed pull requests", "Refactored the sync engine", "Wrote tests for the timer",
                          "Paired on the export sheet", "Fixed a pause edge case"]
        for day in 1...29 {
            let weekday = calendar.component(.weekday, from: calendar.date(byAdding: .day, value: -day, to: today)!)
            let isWeekend = weekday == 1 || weekday == 7
            if !isWeekend {
                // Every second engineering day was both urgent and important.
                completed(engineering, day: day, from: (9, 0), to: (11, 10 + (day % 7) * 5), pause: day % 2 == 0 ? 15 : 0,
                          notes: notesByDay[day % notesByDay.count],
                          priority: day % 2 == 0 ? TaskPriority(isUrgent: true, isImportant: true) : nil)
            }
            if day % 2 == 1 { completed(study, day: day, from: (14, 0), to: (15, 30), pause: day % 4 == 1 ? 10 : 0) }
            if day % 3 == 0 { completed(research, day: day, from: (16, 0), to: (17, 42)) }
            if day % 4 != 0 && !isWeekend { completed(writing, day: day, from: (19, 0), to: (19, 48)) }
            if day % 5 == 2 { completed(design, day: day, from: (12, 0), to: (13, 5)) }
        }
        // A session started by mistake and cancelled: kept, but not in Work Logs or analytics.
        let mistake = WorkSession(templateID: design.id, templateName: design.name, templateIcon: design.symbolName,
                                  templateColorHex: design.colorHex, startedAt: at(3, 18, 0), category: design.category)
        mistake.endedAt = at(3, 18, 2)
        mistake.state = .cancelled
        context.insert(mistake)

        // One quick task, recorded without a template.
        let quickStart = at(1, 17, 30)
        if quickStart < Date() {
            let quick = WorkSession(templateID: nil, templateName: "Fix the release build",
                                    templateIcon: QuickTaskDraft.symbolName, templateColorHex: QuickTaskDraft.color.hex,
                                    startedAt: quickStart, tags: ["build"], notes: "Signing certificate had expired.",
                                    taskPriority: TaskPriority(isUrgent: true, isImportant: true), category: "Development")
            quick.endedAt = quickStart.addingTimeInterval(38 * 60)
            quick.state = .completed
            quick.calendarSyncStatus = .synced
            quick.calendarEventIdentifier = "demo-\(quick.id)"
            context.insert(quick)
        }

        if ["active", "paused", "recovery", "priority"].contains(state) {
            let start = max(todayBase.addingTimeInterval(12 * 60), Date().addingTimeInterval(-(2 * 3600 + 24 * 60 + 18)))
            let session = WorkSession(templateID: engineering.id, templateName: engineering.name, templateIcon: engineering.symbolName,
                                      templateColorHex: engineering.colorHex, startedAt: start, tags: engineering.tags,
                                      notes: "[10:12] Fixed the timer drift bug",
                                      taskPriority: TaskPriority(isUrgent: true, isImportant: true), category: engineering.category)
            let span = Date().timeIntervalSince(start)
            var pauses = [PauseInterval(start: start.addingTimeInterval(span * 0.5), end: start.addingTimeInterval(span * 0.5 + min(25 * 60, span * 0.15)))]
            if state == "paused" { pauses.append(PauseInterval(start: Date().addingTimeInterval(-120))) }
            session.pauses = pauses
            session.state = state == "paused" ? .paused : .active
            session.lastHeartbeatAt = Date().addingTimeInterval(state == "recovery" ? -40 * 60 : 0)
            context.insert(session)
        }
        try? persistence.save()
    }

    /// Writes the menu bar label for each display mode to the sandbox temp
    /// directory (`-demoExportMenuBarLabels`), using the same renderer as the
    /// real menu bar item.
    @MainActor
    private func exportMenuBarLabels() {
        func write(_ image: NSImage?, _ name: String) {
            guard let tiff = image?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: FileManager.default.temporaryDirectory.appending(path: name))
        }
        let colors = (icon: HexColor(hex: "#FF453A")!, name: HexColor(hex: "#0A84FF")!, duration: HexColor(hex: "#30D158")!)
        let styles: [(String, MenuBarConfiguration)] = MenuBarDisplayMode.allCases.flatMap { mode in [
            ("auto", MenuBarConfiguration(displayMode: mode)),
            ("colored", MenuBarConfiguration(displayMode: mode, iconColor: colors.icon, nameColor: colors.name, durationColor: colors.duration)),
            ("background", MenuBarConfiguration(displayMode: mode, durationColor: colors.duration, backgroundColor: colors.name))
        ].map { ("\(mode.rawValue)-\($0.0)", $0.1) } }
        for (name, config) in styles {
            for state in [SessionState.active, .paused] {
                let snapshot = MenuBarSessionSnapshot(templateName: "Software Engineering", templateIcon: "laptopcomputer", state: state,
                                                      activeDuration: 1 * 3600 + 24 * 60 + 37, configuration: config)
                let presentation = MenuBarFormatter.presentation(for: snapshot, showsSeconds: true)
                for scheme in [ColorScheme.light, .dark] {
                    write(MenuBarLabel.renderImage(presentation, colorScheme: scheme),
                          "menubar-\(name)-\(state.rawValue)-\(scheme == .light ? "light" : "dark").png")
                }
            }
        }
        write(MenuBarLabel.identityBadgeImage(), "menubar-identity-badge.png")
        write(MenuBarLabel.identityMarkImage(colorScheme: .light), "menubar-identity-mark-light.png")
        write(MenuBarLabel.identityMarkImage(colorScheme: .dark), "menubar-identity-mark-dark.png")
    }

    /// Actions that need the main window on screen.
    @MainActor
    func presentOnAppear(_ environment: AppEnvironment) {
        if let windowSize {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true || $0.title == "Calendar Time Logger" }) ?? NSApp.mainWindow {
                    var frame = window.frame
                    frame.origin.y += frame.height - windowSize.height
                    frame.size = windowSize
                    window.setFrame(frame, display: true)
                }
            }
        }
        if state == "export" {
            environment.selectedSection = section
            environment.isExportPresented = true
        }
        if state == "quickTask" { environment.isQuickTaskPresented = true }
        if state == "startSession" { environment.isStartSessionPresented = true }
        if state == "priority" { environment.isChangePriorityPresented = true }
        if state == "categories" { environment.isManageCategoriesPresented = true }
        if state == "newTemplate" { environment.isNewTemplatePresented = true }
        if let exportDirectory {
            Task {
                try? await Task.sleep(for: .seconds(1))
                let destination = FixedDestination(url: URL(filePath: exportDirectory).appending(path: "Demo Work Logs.xlsx"))
                let outcome = await environment.exporter.export(scope: .all, filter: nil, columns: exportColumns,
                                                               includesSummary: true, destination: destination)
                print("Demo export: \(outcome)")
            }
        }
    }

    @MainActor
    private final class FixedDestination: ExportDestinationProviding {
        let url: URL
        init(url: URL) { self.url = url }
        func chooseDestination(suggestedName: String) async -> URL? { url }
    }

    @MainActor
    func configure(_ environment: AppEnvironment) {
        if ProcessInfo.processInfo.arguments.contains("-demoExportMenuBarLabels") { exportMenuBarLabels() }
        environment.selectedSection = section
        if state != "recovery" { environment.sessions.dismissRecovery() }
        if state == "completion", let session = try? environment.persistence.completedSessions().first {
            // Present after launch, as it would be after clicking Finish Work.
            Task {
                try? await Task.sleep(for: .seconds(2))
                environment.sessions.lastCompletion = SessionCompletion(
                    log: WorkLog(session: session),
                    calendarOutcome: .created(eventIdentifier: "demo"),
                    calendarName: "Work"
                )
            }
        }
        if section == .workLogs {
            environment.selectedWorkLogID = try? environment.persistence.completedSessions().first?.id
        }
        if section == .templates {
            environment.selectedTemplateID = try? environment.persistence.templates().first?.id
        }
    }
}
/// Sample calendars for demo mode, held in memory. The real calendar list is
/// never read, so no personal calendar name can appear in a demo screenshot.
@MainActor
final class DemoCalendarProvider: CalendarProviding {
    private var stored: [String: CalendarEventRecord] = [:]

    var authorization: CalendarAuthorization { .fullAccess }
    func requestFullAccess() async throws -> Bool { true }

    func calendars() -> [CalendarInfo] {
        [
            CalendarInfo(id: "demo-work", title: "Work", sourceTitle: "iCloud", color: HexColor(hex: "#0A84FF"), allowsModifications: true),
            CalendarInfo(id: "demo-study", title: "Study", sourceTitle: "iCloud", color: HexColor(hex: "#FF453A"), allowsModifications: true),
            CalendarInfo(id: "demo-projects", title: "Projects", sourceTitle: "iCloud", color: HexColor(hex: "#30D158"), allowsModifications: true),
            CalendarInfo(id: "demo-holidays", title: "Holidays", sourceTitle: "Subscribed Calendars", color: HexColor(hex: "#8E8E93"), allowsModifications: false)
        ]
    }

    func systemDefaultCalendarIdentifier() -> String? { "demo-work" }
    func event(withIdentifier identifier: String) -> CalendarEventRecord? { stored[identifier] }

    func saveEvent(_ draft: CalendarEventDraft, existingIdentifier: String?) throws -> CalendarEventRecord {
        let identifier = existingIdentifier ?? "demo-event-\(UUID().uuidString)"
        let record = CalendarEventRecord(identifier: identifier, calendarIdentifier: draft.calendarIdentifier, title: draft.title,
                                         startDate: draft.startDate, endDate: draft.endDate, url: draft.url)
        stored[identifier] = record
        return record
    }

    func removeEvent(withIdentifier identifier: String) throws { stored[identifier] = nil }

    func events(in interval: DateInterval, calendarIdentifiers: [String]?) -> [CalendarEventRecord] {
        stored.values.filter { $0.startDate < interval.end && $0.endDate > interval.start }
    }
}
#endif
