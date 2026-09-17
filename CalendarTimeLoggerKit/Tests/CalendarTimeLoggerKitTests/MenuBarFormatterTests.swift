import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@Suite("Menu bar presentation")
struct MenuBarFormatterTests {
    let duration: TimeInterval = 2 * 3600 + 24 * 60 + 18

    func snapshot(_ config: MenuBarConfiguration, state: SessionState = .active, name: String = "Software Engineering", icon: String = "laptopcomputer") -> MenuBarSessionSnapshot {
        MenuBarSessionSnapshot(templateName: name, templateIcon: icon, state: state, activeDuration: duration, configuration: config)
    }

    func presentation(_ config: MenuBarConfiguration, state: SessionState = .active, showsSeconds: Bool = true) -> MenuBarPresentation {
        MenuBarFormatter.presentation(for: snapshot(config, state: state), showsSeconds: showsSeconds)
    }

    func text(_ config: MenuBarConfiguration, state: SessionState = .active, showsSeconds: Bool = true) -> String {
        presentation(config, state: state, showsSeconds: showsSeconds).plainText
    }

    @Test("Icon + Name + Duration")
    func iconNameAndDuration() {
        let result = presentation(MenuBarConfiguration(displayMode: .iconNameAndDuration))
        #expect(result.plainText == "Software Engineering · 02:24:18")
        #expect(result.iconSymbolName == "laptopcomputer")
        #expect(result.segments.map(\.kind) == [.icon, .separator, .name, .separator, .duration])
    }

    @Test("Name + Duration has no icon")
    func nameAndDuration() {
        let result = presentation(MenuBarConfiguration(displayMode: .nameAndDuration))
        #expect(result.plainText == "Software Engineering · 02:24:18")
        #expect(result.iconSymbolName == nil)
    }

    @Test("Name Only, with and without the icon")
    func nameOnly() {
        #expect(text(MenuBarConfiguration(displayMode: .nameOnly)) == "Software Engineering")
        #expect(presentation(MenuBarConfiguration(displayMode: .nameOnly)).iconSymbolName == "laptopcomputer")
        #expect(presentation(MenuBarConfiguration(displayMode: .nameOnly, showsIconWithName: false)).iconSymbolName == nil)
    }

    @Test("Duration Only")
    func durationOnly() {
        #expect(text(MenuBarConfiguration(displayMode: .durationOnly)) == "02:24:18")
        #expect(text(MenuBarConfiguration(displayMode: .durationOnly), showsSeconds: false) == "02:24")
        #expect(presentation(MenuBarConfiguration(displayMode: .durationOnly)).iconSymbolName == nil)
    }

    @Test("Icon + Duration")
    func iconAndDuration() {
        let result = presentation(MenuBarConfiguration(displayMode: .iconAndDuration))
        #expect(result.plainText == "02:24:18")
        #expect(result.iconSymbolName == "laptopcomputer")
    }

    @Test("Icon Only")
    func iconOnly() {
        let result = MenuBarFormatter.presentation(for: snapshot(MenuBarConfiguration(displayMode: .iconOnly), name: "Study", icon: "book"), showsSeconds: true)
        #expect(result.plainText.isEmpty)
        #expect(result.iconSymbolName == "book")
        #expect(result.symbol == nil)
        #expect(!result.showsIdentity)
        #expect(result.accessibilityLabel.contains("Study"))
    }

    @Test("Every display mode's title and parts are consistent", arguments: MenuBarDisplayMode.allCases)
    func displayModeParts(mode: MenuBarDisplayMode) {
        let result = presentation(MenuBarConfiguration(displayMode: mode, showsIconWithName: false))
        #expect(result.segments.contains { $0.kind == .name } == mode.showsName)
        #expect(result.segments.contains { $0.kind == .duration } == mode.showsDuration)
        #expect(result.segments.contains { $0.kind == .icon } == mode.requiresIcon)
        #expect(!mode.title.isEmpty)
    }

    @Test("Custom separator")
    func customSeparator() {
        #expect(text(MenuBarConfiguration(displayMode: .nameAndDuration, separator: " — ")) == "Software Engineering — 02:24:18")
    }

    @Test("Colors are applied per segment")
    func colorConfiguration() {
        let blue = HexColor(hex: "#0A84FF")!, green = HexColor(hex: "#30D158")!, red = HexColor(hex: "#FF453A")!
        let config = MenuBarConfiguration(displayMode: .iconNameAndDuration, iconColor: red, nameColor: blue, durationColor: green)
        let segments = presentation(config).segments
        #expect(segments.first { $0.kind == .icon }?.color == red)
        #expect(segments.first { $0.kind == .name }?.color == blue)
        #expect(segments.first { $0.kind == .duration }?.color == green)
        #expect(segments.first { $0.kind == .separator }?.color == nil)
        #expect(presentation(config).usesCustomColors)
        #expect(!presentation(.default).usesCustomColors)
    }

    @Test("Background color draws a pill and keeps automatic text legible")
    func backgroundColor() {
        let blue = HexColor(hex: "#0A84FF")!, green = HexColor(hex: "#30D158")!
        let config = MenuBarConfiguration(displayMode: .iconNameAndDuration, durationColor: green, backgroundColor: blue)
        let result = presentation(config)
        #expect(result.backgroundColor == blue)
        #expect(result.usesCustomColors)
        // Automatic foregrounds become the contrasting color; custom ones are kept.
        #expect(result.segments.first { $0.kind == .name }?.color == .white)
        #expect(result.segments.first { $0.kind == .icon }?.color == .white)
        #expect(result.segments.first { $0.kind == .duration }?.color == green)

        let yellow = HexColor(hex: "#FFD60A")!
        #expect(presentation(MenuBarConfiguration(backgroundColor: yellow)).segments.first { $0.kind == .name }?.color == .black)
        #expect(presentation(.default).backgroundColor == nil)
    }

    @Test("Contrast helpers follow WCAG")
    func contrast() {
        #expect(abs(HexColor.white.contrastRatio(with: .black) - 21) < 0.01)
        // Palette colors: white where it's legible (≥ 3:1), black otherwise.
        let expectations: [(String, HexColor)] = [
            ("#0A84FF", .white), ("#FF453A", .white), ("#BF5AF2", .white), ("#5E5CE6", .white),
            ("#FFD60A", .black), ("#30D158", .black), ("#FF9F0A", .black), ("#40C8E0", .black)
        ]
        for (hex, expected) in expectations {
            let color = HexColor(hex: hex)!
            #expect(color.contrastingForeground == expected, "\(hex)")
            #expect(color.contrastRatio(with: color.contrastingForeground) >= 3, "\(hex)")
        }
    }

    @Test("Paused state is communicated with a symbol, not only color")
    func pausedIndicator() {
        let result = presentation(MenuBarConfiguration(displayMode: .iconOnly), state: .paused)
        #expect(result.segments.first?.kind == .pausedIndicator)
        #expect(result.segments.first?.text == "pause.fill")
        #expect(result.segments.first?.isSymbol == true)
        #expect(result.accessibilityLabel.contains("paused"))
    }

    @Test("Hidden templates use a generic symbol")
    func genericSymbols() {
        let hidden = MenuBarConfiguration(isVisible: false)
        #expect(presentation(hidden).symbol == .running)
        #expect(presentation(hidden, state: .paused).symbol == .paused)
        #expect(presentation(hidden).segments.isEmpty)
        #expect(!presentation(hidden).showsIdentity)
    }

    @Test("Legacy emoji and unknown icons never reach the menu bar")
    func legacyIcons() {
        let config = MenuBarConfiguration(displayMode: .iconOnly)
        #expect(MenuBarFormatter.presentation(for: snapshot(config, icon: "💻"), showsSeconds: true).iconSymbolName == "laptopcomputer")
        #expect(MenuBarFormatter.presentation(for: snapshot(config, icon: "not.a.real.symbol"), showsSeconds: true).iconSymbolName == TemplateSymbol.fallbackName)
        let all = MenuBarDisplayMode.allCases.flatMap { mode in
            MenuBarFormatter.presentation(for: snapshot(MenuBarConfiguration(displayMode: mode), state: .paused, icon: "📚"), showsSeconds: true).segments
        }
        #expect(all.allSatisfy { !EmojiDetection.containsEmoji($0.text) })
    }

    @Test("Menu bar service uses the template's live configuration")
    @MainActor
    func serviceUsesTemplateConfiguration() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(name: "Study", icon: "book", menuBar: MenuBarConfiguration(displayMode: .iconOnly))
        let session = try env.sessionService.start(template: template)
        let service = MenuBarService(persistence: env.persistence, settings: env.settings)
        #expect(service.presentation(for: session, now: env.clock.now).iconSymbolName == "book")
        #expect(service.presentation(for: session, now: env.clock.now).plainText.isEmpty)

        var draft = template.draft
        draft.menuBarConfiguration.displayMode = .iconAndDuration
        draft.menuBarConfiguration.backgroundColor = HexColor(hex: "#FF453A")
        try env.persistence.updateTemplate(template, with: draft)
        env.clock.advance(minutes: 61)
        let updated = service.presentation(for: session, now: env.clock.now)
        #expect(updated.plainText == "01:01:00")
        #expect(updated.backgroundColor?.hex == "#FF453A")
    }
}
