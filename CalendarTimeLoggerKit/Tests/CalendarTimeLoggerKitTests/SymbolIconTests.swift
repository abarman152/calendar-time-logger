import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

@MainActor
@Suite("SF Symbol icons")
struct SymbolIconTests {
    @Test("Every catalog symbol exists in the installed SF Symbols")
    func catalogSymbolsRender() {
        let missing = SymbolCatalog.allNames.filter { !SymbolRendering.exists($0) }
        #expect(missing.isEmpty, "Unknown symbols: \(missing)")
    }

    @Test("The catalog is broad and covers the requested categories")
    func catalogBreadth() {
        let titles = SymbolCatalog.categories.map(\.title)
        #expect(titles == ["Development", "Education", "Research", "Writing", "Design", "Business", "Communication",
                           "Productivity", "Files", "Media", "Finance", "Health", "Travel", "Tools", "System",
                           "People", "Objects", "Nature"])
        #expect(SymbolCatalog.allNames.count >= 250)
        #expect(Set(SymbolCatalog.allNames).count == SymbolCatalog.allNames.count)
        #expect(SymbolCatalog.categories.allSatisfy { $0.symbols.count >= 15 })
        #expect(SymbolCatalog.allNames.allSatisfy { TemplateSymbol.looksLikeSymbolName($0) && !EmojiDetection.containsEmoji($0) })
    }

    @Test("Search matches symbol words, system keywords, and categories")
    func search() {
        #expect(SymbolCatalog.search("laptop").contains("laptopcomputer"))
        #expect(SymbolCatalog.search("code").contains("chevron.left.forwardslash.chevron.right"))
        #expect(SymbolCatalog.search("BOOK").contains("book"))
        #expect(SymbolCatalog.search("finance").contains("banknote"))
        #expect(SymbolCatalog.search("", categoryID: "nature").contains("leaf"))
        #expect(!SymbolCatalog.search("", categoryID: "nature").contains("laptopcomputer"))
        #expect(SymbolCatalog.search("", categoryID: nil).count == SymbolCatalog.allNames.count)
        #expect(SymbolCatalog.search("zzzz-no-match").isEmpty)
        #expect(SymbolCatalog.search("book closed").contains("book.closed"))
    }

    @Test("Stored icon values resolve to a valid symbol with a fallback")
    func fallback() {
        #expect(TemplateSymbol.displayName("laptopcomputer") == "laptopcomputer")
        #expect(TemplateSymbol.displayName("not.a.symbol") == TemplateSymbol.fallbackName)
        #expect(TemplateSymbol.displayName("🦄") == TemplateSymbol.fallbackName)
        #expect(TemplateSymbol.displayName("") == TemplateSymbol.fallbackName)
        #expect(TemplateSymbol.normalizedName("   ") == "")
        #expect(SymbolCatalog.contains(TemplateSymbol.fallbackName) && SymbolRendering.exists(TemplateSymbol.fallbackName))
        #expect(SymbolCatalog.contains(TemplateSymbol.defaultName) && SymbolRendering.exists(TemplateSymbol.defaultName))
        #expect(!TemplateSymbol.looksLikeSymbolName("Laptop"))
        #expect(!TemplateSymbol.looksLikeSymbolName("book."))
        #expect(!TemplateSymbol.looksLikeSymbolName("book..closed"))
    }

    @Test("1.0 emoji map to the expected symbols, with or without variation selectors")
    func legacyEmojiMapping() {
        #expect(TemplateSymbol.normalizedName("💻") == "laptopcomputer")
        #expect(TemplateSymbol.normalizedName("📚") == "book")
        #expect(TemplateSymbol.normalizedName("🧪") == "flask")
        #expect(TemplateSymbol.normalizedName("✍️") == "pencil")
        #expect(TemplateSymbol.normalizedName("✍") == "pencil")
        #expect(TemplateSymbol.normalizedName("🎨") == "paintpalette")
        #expect(TemplateSymbol.normalizedName("🏋️") == "dumbbell")
        #expect(TemplateSymbol.normalizedName("🏃🏽") == "figure.run")
        #expect(TemplateSymbol.needsMigration("💼"))
        #expect(!TemplateSymbol.needsMigration("briefcase"))
        #expect(!TemplateSymbol.needsMigration(""))
    }

    @Test("Every legacy mapping target is a real catalog symbol")
    func legacyTargetsAreValid() {
        let invalid = TemplateSymbol.legacyEmojiMap.values.filter { !SymbolCatalog.contains($0) || !SymbolRendering.exists($0) }
        #expect(invalid.isEmpty, "Invalid targets: \(Set(invalid))")
        #expect(TemplateSymbol.legacyEmojiMap.keys.allSatisfy { !$0.unicodeScalars.contains { $0.value == 0xFE0F } })
        // All emoji offered by the 1.0 editor are mapped rather than falling back.
        let suggestions = ["💻", "📚", "🧪", "✍️", "🎨", "📊", "🧠", "📝", "🎧", "🏋️", "📞", "🛠️", "🔬", "📈", "🎓", "💼", "🗂️", "🧾", "🎬", "🌱"]
        #expect(suggestions.allSatisfy { TemplateSymbol.normalizedName($0) != TemplateSymbol.fallbackName })
    }

    @Test("Migration converts templates and session snapshots once, keeping everything else")
    func persistentMigration() throws {
        let env = try TestEnvironment()
        let context = env.persistence.context
        // Simulate a 1.0 store: emoji written directly, bypassing normalization.
        let legacy = try env.makeTemplate(name: "Study", icon: "book", tags: ["learning"])
        legacy.icon = "📚"
        let unknown = try env.makeTemplate(name: "Fun", icon: "gift")
        unknown.icon = "🦄"
        let modern = try env.makeTemplate(name: "Code", icon: "terminal")
        let session = WorkSession(templateID: legacy.id, templateName: "Study", templateIcon: "📚", templateColorHex: "#FF453A",
                                  startedAt: env.clock.now, tags: ["learning"], notes: "Chapter 3")
        session.endedAt = env.clock.now.addingTimeInterval(3600)
        session.state = .completed
        session.calendarEventIdentifier = "event-9"
        context.insert(session)
        let cancelled = WorkSession(templateID: nil, templateName: "Old", templateIcon: "✍️", templateColorHex: "#FF9F0A", startedAt: env.clock.now)
        cancelled.state = .cancelled
        context.insert(cancelled)
        try env.persistence.save()
        let modifiedAt = legacy.modifiedAt

        let result = try env.persistence.migrateLegacyIconsIfNeeded(defaults: env.defaults)
        #expect(result == IconMigrationResult(templates: 2, sessions: 2))
        #expect(legacy.icon == "book")
        #expect(unknown.icon == TemplateSymbol.fallbackName)
        #expect(modern.icon == "terminal")
        #expect(session.templateIcon == "book")
        #expect(cancelled.templateIcon == "pencil")
        // Nothing else changes.
        #expect(session.notes == "Chapter 3")
        #expect(session.calendarEventIdentifier == "event-9")
        #expect(session.templateColorHex == "#FF453A")
        #expect(legacy.modifiedAt == modifiedAt)
        #expect(legacy.tags == ["learning"])

        // Verified through a separate context, as after relaunch.
        let fresh = ModelContext(env.persistence.container)
        let stored = try fresh.fetch(FetchDescriptor<WorkTemplate>()).map(\.icon)
        #expect(stored.allSatisfy { !EmojiDetection.containsEmoji($0) })

        // Runs once.
        legacy.icon = "📚"
        try env.persistence.save()
        #expect(try env.persistence.migrateLegacyIconsIfNeeded(defaults: env.defaults) == IconMigrationResult())
        #expect(legacy.icon == "📚")
        // Even unmigrated values never display as emoji.
        #expect(legacy.symbolName == "book")
    }

    @Test("Work logs and new sessions only carry symbol names")
    func logsAndSessionsUseSymbols() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(name: "Writing", icon: "pencil")
        let session = try env.sessionService.start(template: template)
        #expect(session.templateIcon == "pencil")
        let legacy = WorkLog(templateID: nil, templateName: "Old", templateIcon: "🎨", templateColor: .black,
                             timing: SessionTiming(startedAt: env.clock.now, endedAt: env.clock.now), now: env.clock.now)
        #expect(legacy.templateIcon == "paintpalette")
    }
}
