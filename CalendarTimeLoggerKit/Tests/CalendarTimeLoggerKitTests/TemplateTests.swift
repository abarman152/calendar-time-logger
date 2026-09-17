import Foundation
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("Work templates")
struct TemplateTests {
    @Test("Create a template with defaults")
    func createDefaults() throws {
        let env = try TestEnvironment()
        let template = try env.persistence.createTemplate(WorkTemplateDraft(name: "  Research  ", icon: "flask"), now: env.clock.now)
        #expect(template.name == "Research")
        #expect(template.icon == "flask")
        #expect(template.symbolName == "flask")
        #expect(template.calendarIdentifier == nil)
        #expect(template.menuBarConfiguration == .default)
        #expect(template.menuBarConfiguration.displayMode == .iconNameAndDuration)
        #expect(template.menuBarConfiguration.backgroundColor == nil)
        #expect(template.notificationBehavior == .default)
        #expect(template.createdAt == env.clock.now)
        #expect(template.modifiedAt == env.clock.now)
    }

    @Test("Edit a template updates fields and modification date")
    func editTemplate() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        env.clock.advance(minutes: 5)
        var draft = template.draft
        draft.name = "Engineering"
        draft.tags = ["#Swift", "swift", " macOS "]
        draft.calendarIdentifier = "work"
        draft.icon = "terminal"
        draft.menuBarConfiguration = MenuBarConfiguration(displayMode: .iconOnly, iconColor: HexColor(hex: "#FF453A"), backgroundColor: HexColor(hex: "#0A84FF"))
        draft.notificationBehavior = NotificationBehavior(notifyOnStart: true, reminderIntervalMinutes: 60)
        try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)

        #expect(template.name == "Engineering")
        #expect(template.tags == ["swift", "macos"])
        #expect(template.calendarIdentifier == "work")
        #expect(template.menuBarConfiguration.displayMode == .iconOnly)
        #expect(template.menuBarConfiguration.iconColor?.hex == "#FF453A")
        #expect(template.menuBarConfiguration.backgroundColor?.hex == "#0A84FF")
        #expect(template.icon == "terminal")
        #expect(template.notificationBehavior.reminderIntervalMinutes == 60)
        #expect(template.modifiedAt == env.clock.now)
        #expect(template.modifiedAt > template.createdAt)
    }

    @Test("Delete a template")
    func deleteTemplate() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        try env.persistence.deleteTemplate(template)
        #expect(try env.persistence.templates().isEmpty)
    }

    @Test("Validation rejects empty, duplicate, icon-less, and unknown-icon templates")
    func validation() throws {
        let env = try TestEnvironment()
        try env.makeTemplate()
        #expect(throws: TemplateValidationError.emptyName) {
            try env.persistence.createTemplate(WorkTemplateDraft(name: "   ", icon: "laptopcomputer"))
        }
        #expect(throws: TemplateValidationError.duplicateName("software engineering")) {
            try env.persistence.createTemplate(WorkTemplateDraft(name: "software engineering", icon: "laptopcomputer"))
        }
        #expect(throws: TemplateValidationError.missingIcon) {
            try env.persistence.createTemplate(WorkTemplateDraft(name: "Reading", icon: " "))
        }
        #expect(throws: TemplateValidationError.nameTooLong(max: 60)) {
            try env.persistence.createTemplate(WorkTemplateDraft(name: String(repeating: "a", count: 61), icon: "laptopcomputer"))
        }
        #expect(throws: TemplateValidationError.unknownIcon("made.up.symbol")) {
            try env.persistence.createTemplate(WorkTemplateDraft(name: "Reading", icon: "made.up.symbol"))
        }
        #expect(try env.persistence.templates().count == 1)
    }

    @Test("Renaming a template to its own name is allowed")
    func renameToSelf() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate()
        try env.persistence.updateTemplate(template, with: template.draft)
    }

    @Test("Icons normalize to SF Symbol names, including multi-scalar and legacy emoji")
    func iconNormalization() {
        #expect(WorkTemplateDraft(icon: " laptopcomputer ").normalizedIcon == "laptopcomputer")
        #expect(WorkTemplateDraft(icon: "✍️").normalizedIcon == "pencil")
        #expect(WorkTemplateDraft(icon: "✍️abc").normalizedIcon == "pencil")
        #expect(WorkTemplateDraft(icon: "👩🏽‍💻").normalizedIcon == TemplateSymbol.fallbackName)
        #expect(WorkTemplateDraft(icon: "").normalizedIcon == "")
        // Legacy emoji are accepted and stored as symbols.
        #expect(WorkTemplateDraft(icon: "📚").normalizedIcon == "book")
    }

    @Test("Duplicating a template copies its configuration under a unique name, next to the original")
    func duplicate() throws {
        let env = try TestEnvironment()
        let menuBar = MenuBarConfiguration(displayMode: .iconOnly, backgroundColor: HexColor(hex: "#FF453A"))
        let original = try env.makeTemplate(name: "Study", icon: "book", calendarIdentifier: "work", tags: ["learning"], menuBar: menuBar)
        try env.makeTemplate(name: "Writing", icon: "pencil")
        let copy = try env.persistence.duplicateTemplate(original)
        let second = try env.persistence.duplicateTemplate(original)
        #expect(copy.name == "Study Copy")
        #expect(second.name == "Study Copy 2")
        #expect(copy.id != original.id)
        #expect(copy.icon == "book")
        #expect(copy.calendarIdentifier == "work")
        #expect(copy.tags == ["learning"])
        #expect(copy.menuBarConfiguration == menuBar)
        #expect(try env.persistence.templates().map(\.name) == ["Study", "Study Copy 2", "Study Copy", "Writing"])
    }

    @Test("Default templates use SF Symbols with the documented appearance")
    func defaultTemplates() {
        let drafts = DefaultTemplates.drafts
        #expect(drafts.map(\.icon) == ["laptopcomputer", "book", "flask", "pencil", "paintpalette"])
        #expect(drafts.allSatisfy { SymbolCatalog.contains($0.icon) && SymbolRendering.exists($0.icon) })
        #expect(drafts.allSatisfy { !EmojiDetection.containsEmoji($0.icon) })
        #expect(drafts[0].menuBarConfiguration.displayMode == .iconNameAndDuration)
        #expect(drafts[0].menuBarConfiguration.backgroundColor?.hex == "#0A84FF")
        #expect(drafts[1].menuBarConfiguration.displayMode == .iconOnly)
        #expect(drafts[1].menuBarConfiguration.backgroundColor?.hex == "#FF453A")
    }

    @Test("Templates keep sort order and can be reordered")
    func ordering() throws {
        let env = try TestEnvironment()
        let a = try env.makeTemplate(name: "A")
        let b = try env.makeTemplate(name: "B")
        #expect(try env.persistence.templates().map(\.name) == ["A", "B"])
        try env.persistence.moveTemplates([b, a])
        #expect(try env.persistence.templates().map(\.name) == ["B", "A"])
    }

    @Test("Menu bar configuration round-trips and tolerates missing keys")
    func configurationCoding() throws {
        for mode in MenuBarDisplayMode.allCases {
            let config = MenuBarConfiguration(isVisible: false, displayMode: mode, showsIconWithName: true, separator: " | ",
                                              nameColor: HexColor(hex: "#0A84FF"), durationColor: HexColor(hex: "#30D158"),
                                              backgroundColor: HexColor(hex: "#BF5AF2"))
            let data = try #require(JSONCoding.encode(config))
            #expect(JSONCoding.decode(MenuBarConfiguration.self, from: data) == config)
        }

        let partial = Data(#"{"displayMode":"iconOnly"}"#.utf8)
        let decoded = try #require(JSONCoding.decode(MenuBarConfiguration.self, from: partial))
        #expect(decoded.displayMode == .iconOnly)
        #expect(decoded.isVisible)
        #expect(decoded.separator == MenuBarConfiguration.defaultSeparator)
        #expect(decoded.backgroundColor == nil)
    }

    @Test("1.0 menu bar configurations keep their appearance")
    func legacyConfigurationMigration() throws {
        // 1.0 stored no version; Name + Duration showed the icon unless turned off.
        let withIcon = Data(#"{"displayMode":"nameAndDuration","isVisible":true,"separator":" · ","showsIconWithName":true}"#.utf8)
        #expect(JSONCoding.decode(MenuBarConfiguration.self, from: withIcon)?.displayMode == .iconNameAndDuration)
        let withoutIcon = Data(#"{"displayMode":"nameAndDuration","showsIconWithName":false}"#.utf8)
        #expect(JSONCoding.decode(MenuBarConfiguration.self, from: withoutIcon)?.displayMode == .nameAndDuration)
        let empty = Data("{}".utf8)
        #expect(JSONCoding.decode(MenuBarConfiguration.self, from: empty)?.displayMode == .iconNameAndDuration)
        let nameOnly = Data(##"{"displayMode":"nameOnly","showsIconWithName":true,"nameColor":"#0A84FF"}"##.utf8)
        let decodedNameOnly = try #require(JSONCoding.decode(MenuBarConfiguration.self, from: nameOnly))
        #expect(decodedNameOnly.displayMode == .nameOnly)
        #expect(decodedNameOnly.nameColor?.hex == "#0A84FF")

        // Saved by this version: Name + Duration stays Name + Duration.
        let current = try #require(JSONCoding.encode(MenuBarConfiguration(displayMode: .nameAndDuration)))
        #expect(JSONCoding.decode(MenuBarConfiguration.self, from: current)?.displayMode == .nameAndDuration)
        #expect(String(data: current, encoding: .utf8)?.contains(#""version":2"#) == true)
    }

    @Test("An invalid stored color is ignored rather than failing the whole configuration")
    func invalidColor() throws {
        let data = Data(##"{"version":2,"displayMode":"iconOnly","backgroundColor":"#nothex","iconColor":"#FF453A"}"##.utf8)
        let decoded = try #require(JSONCoding.decode(MenuBarConfiguration.self, from: data))
        #expect(decoded.backgroundColor == nil)
        #expect(decoded.iconColor?.hex == "#FF453A")
    }

    @Test("Colors parse and format as hex")
    func colors() {
        #expect(HexColor(hex: "#0a84ff")?.hex == "#0A84FF")
        #expect(HexColor(hex: "0A84FF") != nil)
        #expect(HexColor(hex: "#XYZ") == nil)
        #expect(TemplatePalette.name(for: HexColor(hex: "#FF453A")!) == "Red")
    }

    @Test("Tag parsing")
    func tags() {
        #expect(TagParsing.parse("#coding, Development  #coding\nswift") == ["coding", "development", "swift"])
        #expect(TagParsing.display(["coding", "development"]) == "#coding #development")
    }
}
