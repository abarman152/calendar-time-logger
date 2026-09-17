import Foundation
import SwiftData

/// The kind of work a template or session belongs to, such as Development or
/// Research.
///
/// Templates and sessions store a category *name* (ADR-025). Templates carry it
/// as a default; each session copies it when it starts and keeps its own value,
/// so renaming, migrating, or deleting a category never rewrites recorded work.
/// The categories a picker offers are the stored `WorkCategoryRecord`s
/// (ADR-027), which the Categories sheet creates, renames, and deletes.
public enum WorkCategory {
    /// The category every template and session has unless one is chosen, and
    /// the value records stored before 1.3 migrate to.
    public static let defaultName = "General"

    public static let maximumLength = 40

    /// Offered on every install, so a first template has sensible choices.
    public static let builtIn = ["Development", "Education", "Research", "Content", "Design", defaultName]

    /// SF Symbol drawn beside a category name. Validated by `scripts/audit-ui-icons.py`.
    public static let symbolName = "folder"

    /// Trims and collapses whitespace. Returns an empty string for a blank name;
    /// validation, not normalization, decides what to do with that.
    public static func normalized(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The value to store: the normalized name, or `defaultName` when blank.
    /// Used where a category must never be undefined (sessions, migrations).
    public static func stored(_ name: String) -> String {
        let value = normalized(name)
        return value.isEmpty ? defaultName : value
    }

    /// Case-insensitive identity, so "development" and "Development" are one category.
    public static func key(_ name: String) -> String {
        stored(name).lowercased()
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        key(lhs) == key(rhs)
    }

    /// Returns the spelling already in use for `name`, if any, so typing
    /// "research" joins the existing "Research" instead of creating a twin.
    public static func canonical(_ name: String, among existing: [String]) -> String {
        let value = stored(name)
        return existing.first { matches($0, value) }.map(stored) ?? value
    }

    /// Built-ins first in their fixed order, then everything else alphabetically.
    /// Names are not deduplicated; the store keeps them unique.
    public static func sorted(_ names: [String]) -> [String] {
        func rank(_ name: String) -> Int { builtIn.firstIndex { matches($0, name) } ?? builtIn.count }
        return names.sorted { lhs, rhs in
            let (l, r) = (rank(lhs), rank(rhs))
            return l != r ? l < r : lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    public static func isDefault(_ name: String) -> Bool { matches(name, defaultName) }

    /// The categories a picker offers: built-ins first in their fixed order,
    /// then every other name in use, alphabetically. Duplicates that differ
    /// only by case appear once.
    public static func available(inUse names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in builtIn where seen.insert(key(name)).inserted {
            result.append(name)
        }
        // The first spelling of a name wins; sorting happens after deduplication
        // so the result doesn't depend on how case variants compare.
        var custom: [String] = []
        for name in names.map(stored) where seen.insert(key(name)).inserted {
            custom.append(name)
        }
        return result + custom.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Validates a category chosen for a template.
    public static func validate(_ name: String) throws(CategoryValidationError) {
        let value = normalized(name)
        guard !value.isEmpty else { throw .empty }
        guard value.count <= maximumLength else { throw .tooLong(max: maximumLength) }
    }
}

/// A category in the stored list. Its `id` never changes, so renaming keeps
/// the same category rather than replacing it.
///
/// Like the other models, every property has a default and there are no unique
/// constraints (CloudKit compatibility); `PersistenceService` keeps names
/// unique without regard to case.
@Model
public final class WorkCategoryRecord {
    public var id: UUID = UUID()
    public var name: String = WorkCategory.defaultName
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = WorkCategory.stored(name)
        self.createdAt = createdAt
        self.modifiedAt = createdAt
    }
}

/// How a category is used right now, for the Categories sheet and its
/// confirmations.
public struct CategoryUsage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// Templates whose category this is, in template order.
    public let templateNames: [String]
    /// Completed work logs recorded with this category name.
    public let workLogCount: Int
    /// Whether the open session (active or paused) has this category.
    public let isUsedByOpenSession: Bool

    public init(id: UUID, name: String, templateNames: [String], workLogCount: Int, isUsedByOpenSession: Bool) {
        self.id = id
        self.name = name
        self.templateNames = templateNames
        self.workLogCount = workLogCount
        self.isUsedByOpenSession = isUsedByOpenSession
    }

    public var templateCount: Int { templateNames.count }

    /// Usage for each category, in the order given. Deleted models are skipped,
    /// so live query results can be passed straight in.
    public static func compute(categories: [WorkCategoryRecord], templates: [WorkTemplate],
                               workLogs: [WorkSession], openSessions: [WorkSession]) -> [CategoryUsage] {
        let templates = templates.filter(\.isLive)
        let logs = workLogs.filter { $0.isLive && $0.state == .completed }
        let open = openSessions.filter { $0.isLive && !$0.state.isTerminal }
        return categories.filter(\.isLive).map { record in
            CategoryUsage(
                id: record.id,
                name: record.name,
                templateNames: templates.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    .filter { WorkCategory.matches($0.category, record.name) }.map(\.name),
                workLogCount: logs.filter { WorkCategory.matches($0.category, record.name) }.count,
                isUsedByOpenSession: open.contains { WorkCategory.matches($0.category, record.name) }
            )
        }
    }
    public var isDefault: Bool { WorkCategory.isDefault(name) }
    /// General can't be renamed or deleted: quick tasks and work without another
    /// category always need it.
    public var canModify: Bool { !isDefault }
}

/// Why a category change was refused. Nothing is changed when one is thrown.
public enum CategoryManagementError: Error, Equatable, LocalizedError {
    case notFound(String)
    case defaultCategoryRequired
    /// Templates use the category, so they must move somewhere first.
    case inUse(name: String, templateCount: Int)
    case destinationNotFound(String)
    case sameDestination

    public var errorDescription: String? {
        switch self {
        case .notFound(let name): "The category “\(name)” no longer exists."
        case .defaultCategoryRequired: "General can’t be renamed or deleted."
        case .inUse(let name, let count):
            count == 1 ? "“\(name)” is used by 1 template." : "“\(name)” is used by \(count) templates."
        case .destinationNotFound(let name): "The category “\(name)” no longer exists."
        case .sameDestination: "Choose a different category to move the templates to."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notFound, .destinationNotFound: "Close the Categories sheet and open it again."
        case .defaultCategoryRequired: "General is where quick tasks and work without another category belong."
        case .inUse: "Move its templates to another category, then delete it."
        case .sameDestination: nil
        }
    }
}

public enum CategoryValidationError: Error, Equatable, LocalizedError {
    case empty
    case tooLong(max: Int)
    case duplicate(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "Choose a category."
        case .tooLong(let max): "Category names can be up to \(max) characters."
        case .duplicate(let name): "A category named “\(name)” already exists."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .empty: "Every template needs a category. Use General if nothing else fits."
        case .tooLong: "Shorten the name."
        case .duplicate: "Choose the existing category, or use a different name."
        }
    }
}
