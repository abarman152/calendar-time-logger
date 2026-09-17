import Foundation
import Observation

public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum AccentPreference: String, CaseIterable, Identifiable, Sendable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    public var id: String { rawValue }
    public var title: String { rawValue == "system" ? "System" : rawValue.capitalized }
}

public enum LayoutDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable, compact
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Global notification switches. A notification is delivered only when the
/// master switch, its category, and (where applicable) the template allow it.
public struct NotificationPreferences: Hashable, Sendable {
    public var isEnabled: Bool
    public var sessionStarted: Bool
    public var reminders: Bool
    public var sessionCompleted: Bool
    public var calendarFailures: Bool
    public var includesTodayTotal: Bool

    public init(
        isEnabled: Bool = true,
        sessionStarted: Bool = true,
        reminders: Bool = true,
        sessionCompleted: Bool = true,
        calendarFailures: Bool = true,
        includesTodayTotal: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.sessionStarted = sessionStarted
        self.reminders = reminders
        self.sessionCompleted = sessionCompleted
        self.calendarFailures = calendarFailures
        self.includesTodayTotal = includesTodayTotal
    }
}

/// User preferences persisted in `UserDefaults`.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let calendarSyncEnabled = "calendar.syncEnabled"
        static let defaultCalendarIdentifier = "calendar.defaultCalendarIdentifier"
        static let includesNotes = "calendar.includesNotes"
        static let includesTags = "calendar.includesTags"
        static let eventTiming = "calendar.eventTiming"
        static let notificationsEnabled = "notifications.enabled"
        static let notifySessionStarted = "notifications.sessionStarted"
        static let notifyReminders = "notifications.reminders"
        static let notifySessionCompleted = "notifications.sessionCompleted"
        static let notifyCalendarFailures = "notifications.calendarFailures"
        static let includesTodayTotal = "notifications.includesTodayTotal"
        static let showsMenuBarItem = "menuBar.showsItem"
        static let menuBarShowsSeconds = "menuBar.showsSeconds"
        static let appearance = "appearance.mode"
        static let accent = "appearance.accent"
        static let density = "appearance.density"
        static let pausesOnSleep = "general.pausesOnSleep"
        static let hasCompletedOnboarding = "general.hasCompletedOnboarding"
        static let defaultDisplayMode = "templates.defaultDisplayMode"
        static let defaultDisplayModeVersion = "templates.defaultDisplayModeVersion"
        static let menuBarIdentityStyle = "menuBar.identityStyle"
        static let dailyGoalMinutes = "general.dailyGoalMinutes"
        static let defaultTemplateID = "general.defaultTemplateID"
        static let opensMainWindowAtLaunch = "general.opensMainWindowAtLaunch"
        static let exportScope = "export.scope"
        static let exportIncludesSummary = "export.includesSummary"
        static let exportRevealsInFinder = "export.revealsInFinder"
        static let exportColumns = "export.columns"
    }

    public var calendarSyncEnabled: Bool { didSet { defaults.set(calendarSyncEnabled, forKey: Key.calendarSyncEnabled) } }
    public var defaultCalendarIdentifier: String? { didSet { defaults.set(defaultCalendarIdentifier, forKey: Key.defaultCalendarIdentifier) } }
    public var includesNotesInEvents: Bool { didSet { defaults.set(includesNotesInEvents, forKey: Key.includesNotes) } }
    public var includesTagsInEvents: Bool { didSet { defaults.set(includesTagsInEvents, forKey: Key.includesTags) } }
    /// How session times are written to Calendar events. Exact by default.
    public var calendarEventTiming: CalendarEventTiming { didSet { defaults.set(calendarEventTiming.rawValue, forKey: Key.eventTiming) } }

    public var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    public var notifySessionStarted: Bool { didSet { defaults.set(notifySessionStarted, forKey: Key.notifySessionStarted) } }
    public var notifyReminders: Bool { didSet { defaults.set(notifyReminders, forKey: Key.notifyReminders) } }
    public var notifySessionCompleted: Bool { didSet { defaults.set(notifySessionCompleted, forKey: Key.notifySessionCompleted) } }
    public var notifyCalendarFailures: Bool { didSet { defaults.set(notifyCalendarFailures, forKey: Key.notifyCalendarFailures) } }
    public var includesTodayTotal: Bool { didSet { defaults.set(includesTodayTotal, forKey: Key.includesTodayTotal) } }

    public var showsMenuBarItem: Bool { didSet { defaults.set(showsMenuBarItem, forKey: Key.showsMenuBarItem) } }
    public var menuBarShowsSeconds: Bool { didSet { defaults.set(menuBarShowsSeconds, forKey: Key.menuBarShowsSeconds) } }
    /// How the permanent CTL item looks when no session is shown.
    public var menuBarIdentityStyle: MenuBarIdentityStyle { didSet { defaults.set(menuBarIdentityStyle.rawValue, forKey: Key.menuBarIdentityStyle) } }

    public var appearance: AppearancePreference { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    public var accent: AccentPreference { didSet { defaults.set(accent.rawValue, forKey: Key.accent) } }
    public var density: LayoutDensity { didSet { defaults.set(density.rawValue, forKey: Key.density) } }

    public var pausesOnSleep: Bool { didSet { defaults.set(pausesOnSleep, forKey: Key.pausesOnSleep) } }
    public var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    /// Display mode applied to newly created templates.
    public var defaultDisplayMode: MenuBarDisplayMode {
        didSet {
            defaults.set(defaultDisplayMode.rawValue, forKey: Key.defaultDisplayMode)
            defaults.set(2, forKey: Key.defaultDisplayModeVersion)
        }
    }
    /// Daily active-work goal shown on the Dashboard. `0` turns the goal off.
    public var dailyGoalMinutes: Int { didSet { defaults.set(dailyGoalMinutes, forKey: Key.dailyGoalMinutes) } }
    /// Template started by the Dashboard's Start Work button. `nil` uses the most recently used template.
    public var defaultTemplateID: UUID? { didSet { defaults.set(defaultTemplateID?.uuidString, forKey: Key.defaultTemplateID) } }
    public var opensMainWindowAtLaunch: Bool { didSet { defaults.set(opensMainWindowAtLaunch, forKey: Key.opensMainWindowAtLaunch) } }

    public var exportScope: WorkLogExportScope { didSet { defaults.set(exportScope.rawValue, forKey: Key.exportScope) } }
    public var exportIncludesSummary: Bool { didSet { defaults.set(exportIncludesSummary, forKey: Key.exportIncludesSummary) } }
    public var exportRevealsInFinder: Bool { didSet { defaults.set(exportRevealsInFinder, forKey: Key.exportRevealsInFinder) } }
    /// Columns and their order for the next export.
    public var exportColumns: WorkLogColumnSelection { didSet { defaults.set(exportColumns.storageValue, forKey: Key.exportColumns) } }

    public static let dailyGoalChoices: [Int] = [0, 60, 120, 180, 240, 300, 360, 420, 480, 540, 600]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        calendarSyncEnabled = bool(Key.calendarSyncEnabled, true)
        defaultCalendarIdentifier = defaults.string(forKey: Key.defaultCalendarIdentifier)
        includesNotesInEvents = bool(Key.includesNotes, true)
        includesTagsInEvents = bool(Key.includesTags, true)
        calendarEventTiming = defaults.string(forKey: Key.eventTiming).flatMap(CalendarEventTiming.init) ?? .default
        notificationsEnabled = bool(Key.notificationsEnabled, true)
        notifySessionStarted = bool(Key.notifySessionStarted, true)
        notifyReminders = bool(Key.notifyReminders, true)
        notifySessionCompleted = bool(Key.notifySessionCompleted, true)
        notifyCalendarFailures = bool(Key.notifyCalendarFailures, true)
        includesTodayTotal = bool(Key.includesTodayTotal, true)
        showsMenuBarItem = bool(Key.showsMenuBarItem, true)
        menuBarShowsSeconds = bool(Key.menuBarShowsSeconds, true)
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearancePreference.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentPreference.init) ?? .system
        density = defaults.string(forKey: Key.density).flatMap(LayoutDensity.init) ?? .comfortable
        pausesOnSleep = bool(Key.pausesOnSleep, false)
        hasCompletedOnboarding = bool(Key.hasCompletedOnboarding, false)
        let storedMode = defaults.string(forKey: Key.defaultDisplayMode).flatMap(MenuBarDisplayMode.init)
        if storedMode == .nameAndDuration, defaults.integer(forKey: Key.defaultDisplayModeVersion) < 2 {
            // 1.0's Name + Duration included the icon, which is now Icon + Name + Duration.
            defaultDisplayMode = .iconNameAndDuration
        } else {
            defaultDisplayMode = storedMode ?? .iconNameAndDuration
        }
        menuBarIdentityStyle = defaults.string(forKey: Key.menuBarIdentityStyle).flatMap(MenuBarIdentityStyle.init) ?? .mark
        dailyGoalMinutes = defaults.object(forKey: Key.dailyGoalMinutes) == nil ? 480 : max(0, defaults.integer(forKey: Key.dailyGoalMinutes))
        defaultTemplateID = defaults.string(forKey: Key.defaultTemplateID).flatMap(UUID.init)
        opensMainWindowAtLaunch = bool(Key.opensMainWindowAtLaunch, true)
        exportScope = defaults.string(forKey: Key.exportScope).flatMap(WorkLogExportScope.init) ?? .all
        exportIncludesSummary = bool(Key.exportIncludesSummary, true)
        exportRevealsInFinder = bool(Key.exportRevealsInFinder, true)
        exportColumns = defaults.string(forKey: Key.exportColumns).flatMap(WorkLogColumnSelection.init(storageValue:)) ?? .default
    }

    public var calendarConfiguration: CalendarConfiguration {
        CalendarConfiguration(
            isSyncEnabled: calendarSyncEnabled,
            defaultCalendarIdentifier: defaultCalendarIdentifier,
            includesNotes: includesNotesInEvents,
            includesTags: includesTagsInEvents,
            eventTiming: calendarEventTiming
        )
    }

    public var notificationPreferences: NotificationPreferences {
        NotificationPreferences(
            isEnabled: notificationsEnabled,
            sessionStarted: notifySessionStarted,
            reminders: notifyReminders,
            sessionCompleted: notifySessionCompleted,
            calendarFailures: notifyCalendarFailures,
            includesTodayTotal: includesTodayTotal
        )
    }
}
