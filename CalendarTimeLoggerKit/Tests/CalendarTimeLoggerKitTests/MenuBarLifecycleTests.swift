import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Menu bar lifecycle")
struct MenuBarLifecycleTests {
    @Test("CTL identity shows at launch with no session")
    func identityAtLaunch() throws {
        let env = try TestEnvironment()
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        #expect(service.isItemInserted)
        let presentation = service.presentation(for: env.sessionService.activeSession, now: env.clock.now)
        #expect(presentation.showsIdentity)
        #expect(presentation.segments.isEmpty)
        #expect(presentation.symbol == nil)
        #expect(presentation.backgroundColor == nil)
        #expect(presentation.accessibilityLabel == MenuBarIdentity.accessibilityLabel)
        #expect(MenuBarIdentity.title == "CTL")
        #expect(SymbolRendering.exists(MenuBarIdentity.symbolName))
    }

    @Test("CTL stays while idle, reflects the session while working, and returns after Finish Work")
    func lifecycle() async throws {
        let env = try TestEnvironment()
        env.settings.calendarSyncEnabled = false
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        let template = try env.makeTemplate(menuBar: MenuBarConfiguration(displayMode: .iconNameAndDuration, backgroundColor: HexColor(hex: "#0A84FF")))

        env.clock.advance(minutes: 30)
        #expect(service.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)

        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 84)
        let working = service.presentation(for: env.sessionService.activeSession, now: env.clock.now)
        #expect(!working.showsIdentity)
        #expect(working.plainText == "Software Engineering · 01:24:00")
        #expect(working.iconSymbolName == "laptopcomputer")
        #expect(working.backgroundColor?.hex == "#0A84FF")
        #expect(service.isItemInserted)

        try env.sessionService.pause()
        let paused = service.presentation(for: env.sessionService.activeSession, now: env.clock.now)
        #expect(paused.segments.first?.kind == .pausedIndicator)
        try env.sessionService.resume()

        try await env.sessionService.finish()
        #expect(service.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)
        #expect(service.isItemInserted)
    }

    @Test("Cancelling a session also returns to the CTL identity")
    func cancelReturnsToIdentity() throws {
        let env = try TestEnvironment()
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        try env.sessionService.start(template: env.makeTemplate())
        #expect(!service.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)
        try env.sessionService.cancel()
        #expect(service.presentation(for: env.sessionService.activeSession, now: env.clock.now).showsIdentity)
    }

    @Test("A session recovered after relaunch is shown immediately")
    func recoveryAfterRelaunch() throws {
        let env = try TestEnvironment()
        try env.sessionService.start(template: env.makeTemplate(name: "Study", icon: "book", menuBar: MenuBarConfiguration(displayMode: .iconOnly)))
        env.relaunch()
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        let presentation = service.presentation(for: env.sessionService.activeSession, now: env.clock.now)
        #expect(!presentation.showsIdentity)
        #expect(presentation.iconSymbolName == "book")
    }

    @Test("The item follows the Show CTL setting, independent of sessions, and the setting persists")
    func visibilitySetting() throws {
        let env = try TestEnvironment()
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        env.settings.showsMenuBarItem = false
        #expect(!service.isItemInserted)
        #expect(!SettingsStore(defaults: env.defaults).showsMenuBarItem)
        env.settings.showsMenuBarItem = true
        #expect(service.isItemInserted)
        #expect(SettingsStore(defaults: env.defaults).menuBarIdentityStyle == .mark)
        env.settings.menuBarIdentityStyle = .text
        #expect(SettingsStore(defaults: env.defaults).menuBarIdentityStyle == .text)
    }

    @Test("A second copy of the app defers to the one already running, so CTL never duplicates")
    func singleInstance() {
        let first = RunningAppInstance(processIdentifier: 500, launchDate: Date(timeIntervalSince1970: 1_000))
        let second = RunningAppInstance(processIdentifier: 400, launchDate: Date(timeIntervalSince1970: 2_000))
        #expect(AppInstancePolicy.instanceToDefer(to: second, among: [first, second]) == first)
        #expect(AppInstancePolicy.instanceToDefer(to: first, among: [first, second]) == nil)
        #expect(AppInstancePolicy.instanceToDefer(to: first, among: [first]) == nil)
        #expect(AppInstancePolicy.instanceToDefer(to: first, among: []) == nil)

        // Simultaneous launches: exactly one copy keeps running.
        let a = RunningAppInstance(processIdentifier: 10, launchDate: Date(timeIntervalSince1970: 5))
        let b = RunningAppInstance(processIdentifier: 11, launchDate: Date(timeIntervalSince1970: 5))
        let c = RunningAppInstance(processIdentifier: 12, launchDate: nil)
        let all = [a, b, c]
        let survivors = all.filter { AppInstancePolicy.instanceToDefer(to: $0, among: all) == nil }
        #expect(survivors == [a])
    }
}
