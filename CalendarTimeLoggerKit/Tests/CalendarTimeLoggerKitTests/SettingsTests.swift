import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Settings")
struct SettingsTests {
    func makeDefaults() -> UserDefaults {
        let suite = "CalendarTimeLoggerSettingsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("New settings have documented defaults and persist")
    func defaultsAndPersistence() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.showsMenuBarItem)
        #expect(settings.menuBarIdentityStyle == .mark)
        #expect(settings.dailyGoalMinutes == 480)
        #expect(settings.defaultTemplateID == nil)
        #expect(settings.opensMainWindowAtLaunch)
        #expect(settings.exportScope == .all)
        #expect(settings.exportIncludesSummary)
        #expect(settings.exportRevealsInFinder)
        #expect(settings.defaultDisplayMode == .iconNameAndDuration)

        let id = UUID()
        settings.menuBarIdentityStyle = .symbol
        settings.dailyGoalMinutes = 0
        settings.defaultTemplateID = id
        settings.opensMainWindowAtLaunch = false
        settings.exportScope = .thisMonth
        settings.exportIncludesSummary = false
        settings.exportRevealsInFinder = false
        settings.defaultDisplayMode = .nameAndDuration

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.menuBarIdentityStyle == .symbol)
        #expect(reloaded.dailyGoalMinutes == 0)
        #expect(reloaded.defaultTemplateID == id)
        #expect(!reloaded.opensMainWindowAtLaunch)
        #expect(reloaded.exportScope == .thisMonth)
        #expect(!reloaded.exportIncludesSummary)
        #expect(!reloaded.exportRevealsInFinder)
        #expect(reloaded.defaultDisplayMode == .nameAndDuration)
        #expect(SettingsStore.dailyGoalChoices.first == 0)
    }

    @Test("1.0's Name + Duration default for new templates keeps showing the icon")
    func legacyDefaultDisplayMode() {
        let defaults = makeDefaults()
        defaults.set("nameAndDuration", forKey: "templates.defaultDisplayMode")
        #expect(SettingsStore(defaults: defaults).defaultDisplayMode == .iconNameAndDuration)
        defaults.set("durationOnly", forKey: "templates.defaultDisplayMode")
        #expect(SettingsStore(defaults: defaults).defaultDisplayMode == .durationOnly)
    }
}
