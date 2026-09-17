import Foundation

/// A session started without a template: the user names the work and classifies
/// it, and the session keeps that name, icon, and color as its own snapshot.
///
/// Quick tasks create no template. They are ordinary sessions with no
/// `templateID`, so Work Logs, analytics, Calendar sync, and export treat them
/// exactly like template-started work.
public struct QuickTaskDraft: Hashable, Sendable {
    public var name: String
    /// Both values are mandatory and always concrete.
    public var taskPriority: TaskPriority
    /// Mandatory; starts as `WorkCategory.defaultName`.
    public var category: String
    public var tags: [String]
    public var notes: String
    /// Explicit calendar for this session. `nil` uses the app default.
    public var calendarIdentifier: String?

    /// Icon and color given to quick tasks, so they are recognizable in Work
    /// Logs and analytics without inventing a template.
    public static let symbolName = "bolt"
    public static let color = HexColor(hex: "#BF5AF2")!

    public init(
        name: String = "",
        taskPriority: TaskPriority = .default,
        category: String = WorkCategory.defaultName,
        tags: [String] = [],
        notes: String = "",
        calendarIdentifier: String? = nil
    ) {
        self.name = name
        self.taskPriority = taskPriority
        self.category = category
        self.tags = tags
        self.notes = notes
        self.calendarIdentifier = calendarIdentifier
    }

    public var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A quick task can start as soon as it has a name. Priority always has a
    /// value, so it can never block the start.
    public var isValid: Bool { !normalizedName.isEmpty && normalizedName.count <= maximumNameLength }

    public var maximumNameLength: Int { TemplateValidator.maximumNameLength }
}
