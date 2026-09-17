import Foundation

/// A top-level destination in the main window's sidebar.
///
/// This is the app's single navigation state: the sidebar selection and the
/// detail view both read `AppEnvironment.selectedSection`.
public enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard, templates, workLogs, calendar, analytics, settings, about

    /// Work destinations at the top of the sidebar (⌘1–⌘5).
    public static let primary: [AppSection] = [.dashboard, .templates, .workLogs, .calendar, .analytics]
    /// App destinations at the bottom of the sidebar.
    public static let secondary: [AppSection] = [.settings, .about]

    /// A section is its own identity. `List(_:selection:)` matches rows to the
    /// selection by `id`, so the ID type must be the selection type. An ID of a
    /// different type (for example `String`) leaves every row unmatched: no row
    /// shows as selected and clicks never change the selection.
    public var id: Self { self }

    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .templates: "Templates"
        case .workLogs: "Work Logs"
        case .calendar: "Calendar"
        case .analytics: "Analytics"
        case .settings: "Settings"
        case .about: "About"
        }
    }

    /// SF Symbol name for the sidebar icon.
    public var symbol: String {
        switch self {
        case .dashboard: "house"
        case .templates: "square.grid.2x2"
        case .workLogs: "list.bullet.rectangle"
        case .calendar: "calendar"
        case .analytics: "chart.bar.xaxis"
        case .settings: "gearshape"
        case .about: "info.circle"
        }
    }

    /// The section to show after the sidebar reports a selection change.
    /// A `nil` selection (for example from clicking empty sidebar space) keeps
    /// the current section, so the detail view is never left without content.
    public static func resolvedSelection(_ proposed: AppSection?, current: AppSection) -> AppSection {
        proposed ?? current
    }
}
