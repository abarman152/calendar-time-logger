import Foundation

/// How a piece of work is classified: urgent, important, both, or neither.
///
/// The two booleans are the stored truth (ADR-022). The four combinations are
/// derived, so analytics, filtering, and export can ask either question
/// independently without a fixed set of categories in the store.
public struct TaskPriority: Codable, Hashable, Sendable {
    public var isUrgent: Bool
    public var isImportant: Bool

    public init(isUrgent: Bool = false, isImportant: Bool = false) {
        self.isUrgent = isUrgent
        self.isImportant = isImportant
    }

    /// The value every template, session, and legacy record starts from.
    public static let `default` = TaskPriority()

    public var quadrant: TaskPriorityQuadrant {
        switch (isUrgent, isImportant) {
        case (true, true): .urgentImportant
        case (true, false): .urgentNotImportant
        case (false, true): .notUrgentImportant
        case (false, false): .neither
        }
    }

    /// `Yes` / `No`, as shown in the UI and written to exports.
    public static func yesNo(_ flag: Bool) -> String { flag ? "Yes" : "No" }

    /// "Urgent, Yes. Important, No." — never relies on color alone.
    public var accessibilityLabel: String {
        "Urgent, \(Self.yesNo(isUrgent)). Important, \(Self.yesNo(isImportant))."
    }

    /// One line for Calendar event notes: "Urgent and important".
    public var sentence: String { quadrant.sentence }
}

/// The four combinations of urgent and important.
public enum TaskPriorityQuadrant: String, CaseIterable, Identifiable, Codable, Sendable {
    case urgentImportant
    case urgentNotImportant
    case notUrgentImportant
    case neither

    public var id: String { rawValue }

    /// Display order runs from the most to the least demanding.
    public static let displayOrder: [TaskPriorityQuadrant] = allCases

    public var priority: TaskPriority {
        switch self {
        case .urgentImportant: TaskPriority(isUrgent: true, isImportant: true)
        case .urgentNotImportant: TaskPriority(isUrgent: true, isImportant: false)
        case .notUrgentImportant: TaskPriority(isUrgent: false, isImportant: true)
        case .neither: TaskPriority()
        }
    }

    public var title: String {
        switch self {
        case .urgentImportant: "Urgent + Important"
        case .urgentNotImportant: "Urgent + Not Important"
        case .notUrgentImportant: "Not Urgent + Important"
        case .neither: "Not Urgent + Not Important"
        }
    }

    /// A short label for charts and narrow cards.
    public var shortTitle: String {
        switch self {
        case .urgentImportant: "Urgent + Important"
        case .urgentNotImportant: "Urgent only"
        case .notUrgentImportant: "Important only"
        case .neither: "Neither"
        }
    }

    public var sentence: String {
        switch self {
        case .urgentImportant: "Urgent and important"
        case .urgentNotImportant: "Urgent, not important"
        case .notUrgentImportant: "Important, not urgent"
        case .neither: "Not urgent, not important"
        }
    }

    /// SF Symbol name. Validated against the installed catalog by
    /// `scripts/audit-ui-icons.py`.
    public var symbolName: String {
        switch self {
        case .urgentImportant: "exclamationmark.2"
        case .urgentNotImportant: "exclamationmark.circle"
        case .notUrgentImportant: "star"
        case .neither: "circle"
        }
    }

    /// Tint used in analytics. Identity is always carried by the symbol and the
    /// label as well, never by color alone.
    public var color: HexColor {
        switch self {
        case .urgentImportant: HexColor(hex: "#FF453A")!
        case .urgentNotImportant: HexColor(hex: "#FF9F0A")!
        case .notUrgentImportant: HexColor(hex: "#0A84FF")!
        case .neither: HexColor(hex: "#8E8E93")!
        }
    }
}

/// Task-priority choices in the Work Logs filter menu. `nil` means “All”.
public enum TaskPriorityFilter: String, CaseIterable, Identifiable, Sendable {
    /// Every urgent session, important or not.
    case urgent
    /// Every important session, urgent or not.
    case important
    case urgentAndImportant
    case neither

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .urgent: "Urgent"
        case .important: "Important"
        case .urgentAndImportant: "Urgent + Important"
        case .neither: "Neither"
        }
    }

    public func matches(_ priority: TaskPriority) -> Bool {
        switch self {
        case .urgent: priority.isUrgent
        case .important: priority.isImportant
        case .urgentAndImportant: priority.isUrgent && priority.isImportant
        case .neither: !priority.isUrgent && !priority.isImportant
        }
    }
}
