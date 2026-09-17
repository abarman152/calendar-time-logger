import CalendarTimeLoggerKit
import ServiceManagement
import SwiftData
import SwiftUI

/// Settings panes, shared by the Settings window and the in-window Settings section.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, menuBar, notifications, appearance, export, calendar, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .appearance: "Appearance"
        case .export: "Export"
        case .calendar: "Calendar"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .appearance: "paintpalette"
        case .export: "square.and.arrow.up"
        case .calendar: "calendar"
        case .privacy: "hand.raised"
        }
    }

    @ViewBuilder @MainActor
    var content: some View {
        switch self {
        case .general: GeneralSettingsView()
        case .menuBar: MenuBarSettingsView()
        case .notifications: NotificationSettingsView()
        case .appearance: AppearanceSettingsView()
        case .export: ExportSettingsView()
        case .calendar: CalendarSettingsView()
        case .privacy: PrivacySettingsView()
        }
    }
}

/// The native Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            ForEach(SettingsPane.allCases) { pane in
                Tab(pane.title, systemImage: pane.symbol) { pane.content }
            }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        .scenePadding()
        .frame(width: 600)
        .frame(minHeight: 420)
    }
}

/// Settings inside the main window, reached from the sidebar.
struct SettingsSectionView: View {
    @State private var pane: SettingsPane = Self.initialPane

    private static var initialPane: SettingsPane {
        #if DEBUG
        // Demo mode: `-demoSettingsPane menuBar` opens a specific pane for screenshots.
        let arguments = ProcessInfo.processInfo.arguments
        if DemoMode.current != nil, let index = arguments.firstIndex(of: "-demoSettingsPane"),
           arguments.indices.contains(index + 1), let pane = SettingsPane(rawValue: arguments[index + 1]) {
            return pane
        }
        #endif
        return .general
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
            pane.content
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var templates: [WorkTemplate]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemMessage: String?

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section("Launch") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
                if let loginItemMessage {
                    HStack {
                        Text(loginItemMessage).font(.caption).foregroundStyle(.secondary)
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Toggle("Show the main window when Calendar Time Logger opens", isOn: $settings.opensMainWindowAtLaunch)
            }
            Section {
                Picker("Default template", selection: $settings.defaultTemplateID) {
                    Text("Most Recently Used").tag(UUID?.none)
                    Divider()
                    ForEach(templates) { template in
                        Label(template.name, systemImage: template.symbolName).tag(UUID?.some(template.id))
                    }
                }
                Picker("Daily goal", selection: $settings.dailyGoalMinutes) {
                    ForEach(SettingsStore.dailyGoalChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : DurationFormatting.short(TimeInterval(minutes * 60))).tag(minutes)
                    }
                }
                Button("Manage Templates…") { environment.show(.templates, openWindow: openWindow) }
            } header: {
                Text("Work")
            } footer: {
                Text("The Dashboard’s Start Work button starts the default template. The daily goal is measured in active work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Pause the session when my Mac sleeps", isOn: $settings.pausesOnSleep)
            } footer: {
                Text("When off, the timer keeps running while your Mac sleeps, since you may still be working away from it. Durations are always calculated from timestamps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Show Welcome Screen Again") {
                    settings.hasCompletedOnboarding = false
                }
            } footer: {
                Text("The welcome screen appears the next time the main window opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemMessage = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Calendar Time Logger in System Settings › General › Login Items." : nil
        } catch {
            loginItemMessage = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct MenuBarSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                Toggle("Show CTL in the menu bar", isOn: $settings.showsMenuBarItem)
                Picker("When not working, show", selection: $settings.menuBarIdentityStyle) {
                    ForEach(MenuBarIdentityStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .disabled(!settings.showsMenuBarItem)
                LabeledContent("Preview") {
                    IdentityPreview(style: settings.menuBarIdentityStyle)
                }
            } header: {
                Text("Calendar Time Logger Item")
            } footer: {
                Text("The CTL item stays in the menu bar while Calendar Time Logger runs, whether or not you’re working, and is removed when the app quits. During a session it shows the running template. When it’s hidden, use the main window or the Session menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show seconds in the duration", isOn: $settings.menuBarShowsSeconds)
                Picker("Display for new templates", selection: $settings.defaultDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("During a Session")
            } footer: {
                Text("Each template sets its own display, icon, text colors, and background in the template editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private struct IdentityPreview: View {
        let style: MenuBarIdentityStyle

        var body: some View {
            HStack(spacing: 6) {
                strip(.light)
                strip(.dark)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(style.title) preview")
        }

        private func strip(_ scheme: ColorScheme) -> some View {
            Group {
                switch style {
                case .mark:
                    if let image = MenuBarLabel.identityMarkImage(colorScheme: scheme) {
                        Image(nsImage: image)
                    }
                case .badge:
                    if let image = MenuBarLabel.identityBadgeImage() {
                        Image(nsImage: image).renderingMode(.template)
                    }
                case .text:
                    Text(MenuBarIdentity.title).font(.system(size: 13, weight: .semibold))
                case .symbol:
                    Image(systemName: MenuBarIdentity.symbolName)
                }
            }
            .foregroundStyle(scheme == .light ? Color.black : Color.white)
            .frame(width: 56, height: 24)
            .background(scheme == .light ? Color(white: 0.92) : Color(white: 0.16), in: .rect(cornerRadius: 6))
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                LabeledContent("System permission", value: environment.notifications.authorization.displayName)
                if environment.notifications.authorization == .denied {
                    Button("Open Notification Settings") { environment.openNotificationSettings() }
                } else if environment.notifications.authorization == .notDetermined {
                    Button("Allow Notifications") {
                        Task { await environment.notifications.requestAuthorizationIfNeeded() }
                    }
                }
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
            }
            Section {
                Toggle("Session starts", isOn: $settings.notifySessionStarted)
                Toggle("Session ends", isOn: $settings.notifySessionCompleted)
                Toggle("Include today’s total when a session ends", isOn: $settings.includesTodayTotal)
                    .disabled(!settings.notifySessionCompleted)
                Toggle("Long session reminders", isOn: $settings.notifyReminders)
                Toggle("Calendar sync problems", isOn: $settings.notifyCalendarFailures)
            } header: {
                Text("Deliver")
            } footer: {
                Text("Start, end, and reminder notifications are also set per template. Reminders count only active time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.notificationsEnabled)
        }
        .formStyle(.grouped)
        .task { await environment.notifications.refreshAuthorization() }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Accent color", selection: $settings.accent) {
                ForEach(AccentPreference.allCases) { accent in
                    Text(accent.title).tag(accent)
                }
            }
            Picker("Layout density", selection: $settings.density) {
                ForEach(LayoutDensity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }
}

private struct ExportSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = environment.settings
        Form {
            Section {
                LabeledContent("Format") {
                    Label("Excel Workbook (.xlsx)", systemImage: "tablecells")
                }
                Picker("Default scope", selection: $settings.exportScope) {
                    ForEach(WorkLogExportScope.allCases.filter { $0 != .currentFilter }) { Text($0.title).tag($0) }
                }
                Toggle("Include a Summary sheet", isOn: $settings.exportIncludesSummary)
                Toggle("Show the exported file in Finder", isOn: $settings.exportRevealsInFinder)
                LabeledContent("Columns") {
                    HStack(spacing: 8) {
                        Text("\(settings.exportColumns.count) of \(WorkLogExportColumn.allCases.count) selected")
                            .foregroundStyle(.secondary)
                        Button("Reset") { settings.exportColumns = .default }
                            .controlSize(.small)
                            .disabled(settings.exportColumns == .default)
                            .help("Restore the default columns")
                    }
                }
                Button("Export Work Logs…") { environment.requestExport() }
            } footer: {
                Text("Exports include completed sessions only. Choose the columns and their order in the export sheet: date, start and end times, durations, template, category, Urgent, Important, task priority, tags, notes, calendar, and Calendar event status. You choose where each file is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarSettingsView: View {
    var body: some View {
        Form {
            CalendarAccessSection()
            CalendarDefaultsSection()
            CalendarEventTimesSection()
            Section {
                LabeledContent("Event color", value: "Set by each event’s calendar")
            } header: {
                Text("Event Appearance")
            } footer: {
                Text("Apple Calendar colors events by calendar, and EventKit has no per-event color. Choose calendars with the colors you want for each template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Form {
            Section("Stored on This Mac") {
                Text("Templates, work sessions, notes, tags, and settings are stored locally by Calendar Time Logger. It doesn’t sync with iCloud and makes no network requests of its own.")
            }
            Section("Sent to Apple Calendar") {
                Text("When a session is finished and Calendar sync is on: the template name, start and finish times, a summary with active and paused time, and optionally tags and notes. Calendar may sync that event to accounts you’ve set up, such as iCloud or Google.")
            }
            Section("Exports") {
                Text("Excel exports are written only to the location you choose in the Save panel.")
            }
            Section("Permissions") {
                LabeledContent("Calendar", value: environment.calendar.authorization.displayName)
                LabeledContent("Notifications", value: environment.notifications.authorization.displayName)
                Button("Open Privacy & Security Settings") { environment.openCalendarPrivacySettings() }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    private static let website = URL(string: "https://abirbarman.com")

    var body: some View {
        VStack(spacing: 12) {
            Image("BrandLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 116, height: 116)
                .accessibilityLabel("Calendar Time Logger logo")
            Text("Calendar Time Logger")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                .foregroundStyle(.secondary)
            Text("Record real work live. Apple Calendar is the output.")
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text("Developed by Abir Barman")
                if let website = Self.website {
                    Link("abirbarman.com", destination: website)
                        .help("Open abirbarman.com in your browser")
                }
            }
            .font(.callout)
            .padding(.top, 4)
            Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

/// About inside the main window.
struct AboutSectionView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AboutView()
                VStack(alignment: .leading, spacing: 10) {
                    Label("Live work is the source of truth. A Calendar event is created only when you finish a session, using its real start and finish times.", systemImage: "checkmark.seal")
                    Label("Your data stays on this Mac. There is no account, sync service, or tracking.", systemImage: "lock.shield")
                    Label("Icons are SF Symbols.", systemImage: "square.grid.2x2")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520, alignment: .leading)
                .card()
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About")
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–" }
}
