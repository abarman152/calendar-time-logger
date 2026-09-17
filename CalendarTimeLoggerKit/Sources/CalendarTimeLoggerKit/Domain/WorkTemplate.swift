import Foundation
import SwiftData

/// Describes how a type of work is recorded — not when it happens.
///
/// Every stored property has a default value and there are no unique
/// constraints, keeping the model compatible with future CloudKit sync.
@Model
public final class WorkTemplate {
    public var id: UUID = UUID()
    public var name: String = ""
    /// SF Symbol name (see `SymbolCatalog`). Templates created by 1.0 stored an
    /// emoji here; `IconMigration` converts those at launch.
    public var icon: String = TemplateSymbol.defaultName
    public var colorHex: String = "#0A84FF"
    /// The category sessions started from this template begin with. Always a
    /// name; templates stored before 1.3 read as `WorkCategory.defaultName`
    /// (ADR-025).
    public var category: String = WorkCategory.defaultName
    /// Calendar override for this template. `nil` uses the global default.
    public var calendarIdentifier: String?
    public var tags: [String] = []
    public var notes: String = ""
    /// Default task classification for sessions started from this template.
    /// Both flags always have a value; templates stored before 1.2 read as
    /// `false` (ADR-022).
    public var isUrgent: Bool = false
    public var isImportant: Bool = false
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    // Value-type configurations are stored as JSON so they can evolve without
    // schema migrations; use the typed accessors below.
    var menuBarConfigurationData: Data?
    var notificationBehaviorData: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        color: HexColor,
        category: String = WorkCategory.defaultName,
        calendarIdentifier: String? = nil,
        tags: [String] = [],
        notes: String = "",
        taskPriority: TaskPriority = .default,
        notificationBehavior: NotificationBehavior = .default,
        menuBarConfiguration: MenuBarConfiguration = .default,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = TemplateSymbol.normalizedName(icon)
        self.colorHex = color.hex
        self.category = WorkCategory.stored(category)
        self.calendarIdentifier = calendarIdentifier
        self.tags = tags
        self.notes = notes
        self.isUrgent = taskPriority.isUrgent
        self.isImportant = taskPriority.isImportant
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.menuBarConfigurationData = JSONCoding.encode(menuBarConfiguration)
        self.notificationBehaviorData = JSONCoding.encode(notificationBehavior)
    }

    public var color: HexColor {
        get { HexColor(hex: colorHex) ?? TemplatePalette.colors[0].color }
        set { colorHex = newValue.hex }
    }

    /// The symbol to draw. Always a catalog symbol, even for legacy values.
    public var symbolName: String { TemplateSymbol.displayName(icon) }

    /// The template's default task classification.
    public var taskPriority: TaskPriority {
        get { TaskPriority(isUrgent: isUrgent, isImportant: isImportant) }
        set {
            isUrgent = newValue.isUrgent
            isImportant = newValue.isImportant
        }
    }

    public var menuBarConfiguration: MenuBarConfiguration {
        get { JSONCoding.decode(MenuBarConfiguration.self, from: menuBarConfigurationData) ?? .default }
        set { menuBarConfigurationData = JSONCoding.encode(newValue) }
    }

    public var notificationBehavior: NotificationBehavior {
        get { JSONCoding.decode(NotificationBehavior.self, from: notificationBehaviorData) ?? .default }
        set { notificationBehaviorData = JSONCoding.encode(newValue) }
    }

    /// A value snapshot used by UI and services that should not hold the model.
    public var draft: WorkTemplateDraft {
        WorkTemplateDraft(
            name: name,
            icon: icon,
            color: color,
            category: category,
            calendarIdentifier: calendarIdentifier,
            tags: tags,
            notes: notes,
            taskPriority: taskPriority,
            notificationBehavior: notificationBehavior,
            menuBarConfiguration: menuBarConfiguration
        )
    }

    public func apply(_ draft: WorkTemplateDraft, modifiedAt date: Date = Date()) {
        name = draft.normalizedName
        icon = draft.normalizedIcon
        color = draft.color
        category = draft.normalizedCategory
        calendarIdentifier = draft.calendarIdentifier
        tags = TagParsing.normalize(draft.tags)
        notes = draft.notes
        taskPriority = draft.taskPriority
        notificationBehavior = draft.notificationBehavior
        menuBarConfiguration = draft.menuBarConfiguration
        modifiedAt = date
    }
}

/// Editable value representation of a template.
public struct WorkTemplateDraft: Hashable, Sendable {
    public var name: String
    public var icon: String
    public var color: HexColor
    /// Mandatory. A blank value fails validation rather than being stored.
    public var category: String
    public var calendarIdentifier: String?
    public var tags: [String]
    public var notes: String
    /// Always a concrete Yes/No pair; there is no unconfigured state.
    public var taskPriority: TaskPriority
    public var notificationBehavior: NotificationBehavior
    public var menuBarConfiguration: MenuBarConfiguration

    public init(
        name: String = "",
        icon: String = TemplateSymbol.defaultName,
        color: HexColor = TemplatePalette.colors[0].color,
        category: String = WorkCategory.defaultName,
        calendarIdentifier: String? = nil,
        tags: [String] = [],
        notes: String = "",
        taskPriority: TaskPriority = .default,
        notificationBehavior: NotificationBehavior = .default,
        menuBarConfiguration: MenuBarConfiguration = .default
    ) {
        self.name = name
        self.icon = icon
        self.color = color
        self.category = category
        self.calendarIdentifier = calendarIdentifier
        self.tags = tags
        self.notes = notes
        self.taskPriority = taskPriority
        self.notificationBehavior = notificationBehavior
        self.menuBarConfiguration = menuBarConfiguration
    }

    public var normalizedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The icon as an SF Symbol name. Legacy emoji are mapped to symbols.
    public var normalizedIcon: String { TemplateSymbol.normalizedName(icon) }
    /// The category with whitespace tidied. Empty when the user cleared it.
    public var normalizedCategory: String { WorkCategory.normalized(category) }
}

public enum TemplateValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case nameTooLong(max: Int)
    case duplicateName(String)
    case missingIcon
    case unknownIcon(String)
    case invalidCategory(CategoryValidationError)

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Give the template a name."
        case .nameTooLong(let max): "Template names can be up to \(max) characters."
        case .duplicateName(let name): "A template named “\(name)” already exists."
        case .missingIcon: "Choose an icon for the template."
        case .unknownIcon(let name): "“\(name)” isn’t an available icon. Choose one from the icon picker."
        case .invalidCategory(let error): error.errorDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidCategory(let error): error.recoverySuggestion
        default: nil
        }
    }
}

public enum TemplateValidator {
    public static let maximumNameLength = 60

    /// Validates a draft against existing template names (case-insensitive).
    public static func validate(_ draft: WorkTemplateDraft, existingNames: [String]) throws {
        let name = draft.normalizedName
        guard !name.isEmpty else { throw TemplateValidationError.emptyName }
        guard name.count <= maximumNameLength else {
            throw TemplateValidationError.nameTooLong(max: maximumNameLength)
        }
        let icon = draft.normalizedIcon
        guard !icon.isEmpty else { throw TemplateValidationError.missingIcon }
        guard SymbolCatalog.contains(icon) else { throw TemplateValidationError.unknownIcon(icon) }
        do {
            try WorkCategory.validate(draft.category)
        } catch {
            throw TemplateValidationError.invalidCategory(error)
        }
        if existingNames.contains(where: { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }) {
            throw TemplateValidationError.duplicateName(name)
        }
    }
}

/// The templates created on first launch.
public enum DefaultTemplates {
    public static var drafts: [WorkTemplateDraft] {
        let blue = HexColor(hex: "#0A84FF")!, red = HexColor(hex: "#FF453A")!, green = HexColor(hex: "#30D158")!
        let orange = HexColor(hex: "#FF9F0A")!, purple = HexColor(hex: "#BF5AF2")!
        return [
            WorkTemplateDraft(name: "Software Engineering", icon: "laptopcomputer", color: blue, category: "Development", tags: ["coding", "development"],
                              menuBarConfiguration: MenuBarConfiguration(displayMode: .iconNameAndDuration, backgroundColor: blue)),
            WorkTemplateDraft(name: "Study", icon: "book", color: red, category: "Education", tags: ["learning"],
                              menuBarConfiguration: MenuBarConfiguration(displayMode: .iconOnly, backgroundColor: red)),
            WorkTemplateDraft(name: "Research", icon: "flask", color: green, category: "Research", tags: ["research"],
                              menuBarConfiguration: MenuBarConfiguration(displayMode: .iconAndDuration)),
            WorkTemplateDraft(name: "Writing", icon: "pencil", color: orange, category: "Content", tags: ["writing"],
                              menuBarConfiguration: MenuBarConfiguration(displayMode: .iconNameAndDuration)),
            WorkTemplateDraft(name: "Design", icon: "paintpalette", color: purple, category: "Design", tags: ["design"],
                              menuBarConfiguration: MenuBarConfiguration(displayMode: .iconNameAndDuration))
        ]
    }
}
