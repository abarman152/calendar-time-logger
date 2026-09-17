import Testing
@testable import CalendarTimeLoggerKit

@Suite("Sidebar navigation")
struct AppSectionTests {
    @Test("Navigation state represents every sidebar destination, in sidebar order")
    func allDestinations() {
        #expect(AppSection.allCases == [.dashboard, .templates, .workLogs, .calendar, .analytics, .settings, .about])
        #expect(AppSection.allCases.map(\.title) == ["Dashboard", "Templates", "Work Logs", "Calendar", "Analytics", "Settings", "About"])
        #expect(AppSection.primary == [.dashboard, .templates, .workLogs, .calendar, .analytics])
        #expect(AppSection.secondary == [.settings, .about])
        #expect(AppSection.primary + AppSection.secondary == AppSection.allCases)
    }

    @Test("Row identity is the section itself, matching the List selection type")
    func identityMatchesSelectionType() {
        // Regression: `id` was a `String`, so List rows never matched the
        // `AppSection?` selection and sidebar clicks did nothing.
        #expect(AppSection.ID.self == AppSection.self)
        for section in AppSection.allCases {
            #expect(section.id == section)
        }
    }

    @Test("Selecting each section navigates to it", arguments: AppSection.allCases, AppSection.allCases)
    func selectionChangesSection(current: AppSection, proposed: AppSection) {
        #expect(AppSection.resolvedSelection(proposed, current: current) == proposed)
    }

    @Test("A cleared selection keeps the current section", arguments: AppSection.allCases)
    func nilSelectionKeepsCurrent(current: AppSection) {
        #expect(AppSection.resolvedSelection(nil, current: current) == current)
    }

    @Test("Titles and symbols are unique, present, and real SF Symbols")
    func titlesAndSymbols() {
        #expect(Set(AppSection.allCases.map(\.title)).count == AppSection.allCases.count)
        #expect(Set(AppSection.allCases.map(\.symbol)).count == AppSection.allCases.count)
        #expect(AppSection.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(AppSection.allCases.allSatisfy { SymbolRendering.exists($0.symbol) })
    }

    @Test("Raw values stay stable for launch arguments")
    func rawValues() {
        #expect(AppSection.allCases.map(\.rawValue) == ["dashboard", "templates", "workLogs", "calendar", "analytics", "settings", "about"])
        #expect(AppSection(rawValue: "workLogs") == .workLogs)
    }
}
