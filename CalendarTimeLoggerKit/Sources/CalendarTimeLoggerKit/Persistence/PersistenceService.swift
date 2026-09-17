import Foundation
import SwiftData

/// Version 4 adds `WorkCategoryRecord`, the stored list of categories with a
/// stable identity (ADR-027). Templates and sessions are unchanged: a template
/// names its category, and a session keeps the name it was recorded with.
///
/// These are the models the app actually uses. Versions 1–3 keep their own
/// frozen copies in `SchemaV1.swift`, `SchemaV2.swift`, and `SchemaV3.swift`; a
/// future version 5 adds another `VersionedSchema` with frozen copies of *this*
/// shape, plus a stage below.
public enum CalendarTimeLoggerSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] { [WorkTemplate.self, WorkSession.self, WorkCategoryRecord.self] }
}

public typealias CalendarTimeLoggerCurrentSchema = CalendarTimeLoggerSchemaV4

public enum CalendarTimeLoggerMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CalendarTimeLoggerSchemaV1.self, CalendarTimeLoggerSchemaV2.self, CalendarTimeLoggerSchemaV3.self, CalendarTimeLoggerSchemaV4.self]
    }

    /// Adding attributes that have defaults, or a new entity, is a lightweight
    /// change: no data is rewritten and nothing is lost. The category list a
    /// version 4 store starts with is filled in after opening, by
    /// `PersistenceService.reconcileCategories()`.
    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: CalendarTimeLoggerSchemaV1.self, toVersion: CalendarTimeLoggerSchemaV2.self),
            .lightweight(fromVersion: CalendarTimeLoggerSchemaV2.self, toVersion: CalendarTimeLoggerSchemaV3.self),
            .lightweight(fromVersion: CalendarTimeLoggerSchemaV3.self, toVersion: CalendarTimeLoggerSchemaV4.self)
        ]
    }
}

public enum PersistenceError: Error, LocalizedError, Equatable {
    case storeUnavailable(String)
    case saveFailed(String)
    /// The item was deleted, for example from another window, before the change was saved.
    case itemDeleted

    public var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            "Calendar Time Logger couldn’t open its database, so new work can’t be recorded."
        case .saveFailed:
            "Calendar Time Logger couldn’t save your change."
        case .itemDeleted:
            "This item was deleted, so the change wasn’t saved."
        }
    }

    public var failureReason: String? {
        switch self {
        case .storeUnavailable(let reason), .saveFailed(let reason): reason
        case .itemDeleted: nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .storeUnavailable, .saveFailed:
            "Make sure your disk has free space, then quit and reopen Calendar Time Logger."
        case .itemDeleted:
            "Select another item and try again."
        }
    }
}

/// Owns the SwiftData container and provides typed fetches.
@MainActor
public final class PersistenceService {
    public let container: ModelContainer
    /// Set when the on-disk store could not be opened and a temporary
    /// in-memory store is in use. Recording is disabled in that state.
    public let storeError: PersistenceError?

    public var context: ModelContext { container.mainContext }
    public var canRecordWork: Bool { storeError == nil }

    init(container: ModelContainer, storeError: PersistenceError?) {
        self.container = container
        self.storeError = storeError
    }

    /// Opens the on-disk store in Application Support. Sync with iCloud is
    /// explicitly disabled for V1.
    public static func makeDefault() -> PersistenceService {
        do {
            return try open(url: try storeDirectory().appending(path: "CalendarTimeLogger.store"))
        } catch {
            // Fall back to memory so the app can still show the error and any
            // Calendar/Settings UI, but refuse to record work that would be lost.
            let fallback = try! makeInMemoryContainer()
            return PersistenceService(container: fallback, storeError: .storeUnavailable(error.localizedDescription))
        }
    }

    /// Opens (and if necessary migrates) the store at `url`. `makeDefault()`
    /// uses the Application Support location; tests and the DEBUG demo's
    /// persistent store use a temporary file.
    public static func open(url: URL) throws -> PersistenceService {
        let schema = Schema(versionedSchema: CalendarTimeLoggerCurrentSchema.self)
        let configuration = ModelConfiguration(
            "CalendarTimeLogger",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CalendarTimeLoggerMigrationPlan.self,
            configurations: configuration
        )
        let service = PersistenceService(container: container, storeError: nil)
        // A store migrated from 1.3 has no category list yet. A failure here is
        // retried by the next category read, so it doesn't stop the store opening.
        _ = try? service.reconcileCategories()
        return service
    }

    /// An in-memory store for tests and previews.
    public static func inMemory() throws -> PersistenceService {
        let service = PersistenceService(container: try makeInMemoryContainer(), storeError: nil)
        _ = try? service.reconcileCategories()
        return service
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CalendarTimeLoggerCurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func storeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appending(path: "Calendar Time Logger", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Saving

    public func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: Templates

    public func templates() throws -> [WorkTemplate] {
        try context.fetch(FetchDescriptor<WorkTemplate>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    public func template(id: UUID?) -> WorkTemplate? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<WorkTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    public func createTemplate(_ draft: WorkTemplateDraft, now: Date = Date()) throws -> WorkTemplate {
        let existing = try templates()
        try TemplateValidator.validate(draft, existingNames: existing.map(\.name))
        var draft = draft
        draft.category = WorkCategory.canonical(draft.category, among: try availableCategories())
        let template = WorkTemplate(name: draft.normalizedName, icon: draft.normalizedIcon, color: draft.color,
                                    sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1, createdAt: now)
        template.apply(draft, modifiedAt: now)
        context.insert(template)
        do {
            try save()
        } catch {
            context.delete(template)
            throw error
        }
        _ = try? reconcileCategories(now: now)
        return template
    }

    public func updateTemplate(_ template: WorkTemplate, with draft: WorkTemplateDraft, now: Date = Date()) throws {
        guard template.isLive else { throw PersistenceError.itemDeleted }
        let others = try templates().filter { $0.id != template.id }
        try TemplateValidator.validate(draft, existingNames: others.map(\.name))
        var draft = draft
        draft.category = WorkCategory.canonical(draft.category, among: try availableCategories())
        template.apply(draft, modifiedAt: now)
        try save()
        _ = try? reconcileCategories(now: now)
    }

    // MARK: Categories

    /// The stored categories, built-ins first, then alphabetically.
    public func categories() throws -> [WorkCategoryRecord] {
        let records = try context.fetch(FetchDescriptor<WorkCategoryRecord>())
        let order = WorkCategory.sorted(records.map(\.name))
        return records.sorted { (order.firstIndex(of: $0.name) ?? 0) < (order.firstIndex(of: $1.name) ?? 0) }
    }

    public func category(id: UUID) -> WorkCategoryRecord? {
        var descriptor = FetchDescriptor<WorkCategoryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Every category a picker should offer, in display order.
    public func availableCategories() throws -> [String] {
        try reconcileCategories()
        return try categories().map(\.name)
    }

    /// Makes the stored category list complete. Safe to call any number of times.
    ///
    /// - An empty list (a new install, or a store just migrated from 1.3) gets
    ///   the built-in categories.
    /// - General is always present.
    /// - Every category a template names is present, so a template can never
    ///   point at a category the Categories sheet doesn't show.
    /// - Names that differ only by case are merged into the oldest record.
    ///
    /// Recorded sessions never add categories: a deleted category stays deleted
    /// even though old work logs still carry its name.
    @discardableResult
    public func reconcileCategories(now: Date = Date()) throws -> Int {
        guard canRecordWork else { return 0 }
        var records = try context.fetch(FetchDescriptor<WorkCategoryRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        var inserted: [WorkCategoryRecord] = []
        var removed: [WorkCategoryRecord] = []
        func insert(_ name: String) {
            let record = WorkCategoryRecord(name: name, createdAt: now)
            context.insert(record)
            records.append(record)
            inserted.append(record)
        }

        var seen: [String: WorkCategoryRecord] = [:]
        for record in records {
            if seen[WorkCategory.key(record.name)] != nil {
                removed.append(record)
            } else {
                seen[WorkCategory.key(record.name)] = record
            }
        }
        for record in removed { context.delete(record) }
        records.removeAll { record in removed.contains { $0 === record } }

        if records.isEmpty {
            WorkCategory.builtIn.forEach(insert)
        }
        if !records.contains(where: { WorkCategory.isDefault($0.name) }) {
            insert(WorkCategory.defaultName)
        }
        for template in try templates() where !records.contains(where: { WorkCategory.matches($0.name, template.category) }) {
            insert(WorkCategory.stored(template.category))
        }

        let changes = inserted.count + removed.count
        guard changes > 0 else { return 0 }
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
        return changes
    }

    /// Where each category is used right now.
    public func categoryUsage(openSession: WorkSession? = nil) throws -> [CategoryUsage] {
        try reconcileCategories()
        return CategoryUsage.compute(
            categories: try categories(),
            templates: try templates(),
            workLogs: try completedSessions(),
            openSessions: try openSession.map { [$0] } ?? openSessions()
        )
    }

    /// Adds a category no template uses yet.
    ///
    /// The name is tidied first. A name that matches an existing category
    /// without regard to case is refused as a duplicate, so a repeated Add can't
    /// create a second copy.
    @discardableResult
    public func createCategory(named name: String, now: Date = Date()) throws -> WorkCategoryRecord {
        try WorkCategory.validate(name)
        try reconcileCategories(now: now)
        let value = WorkCategory.normalized(name)
        if let existing = try categories().first(where: { WorkCategory.matches($0.name, value) }) {
            throw CategoryValidationError.duplicate(existing.name)
        }
        let record = WorkCategoryRecord(name: value, createdAt: now)
        context.insert(record)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
        return record
    }

    /// Returns the existing category for `name`, creating it when there is none.
    /// Used where the user types a category in place.
    @discardableResult
    public func categoryNamed(_ name: String, now: Date = Date()) throws -> WorkCategoryRecord {
        try WorkCategory.validate(name)
        try reconcileCategories(now: now)
        if let existing = try categories().first(where: { WorkCategory.matches($0.name, name) }) {
            return existing
        }
        return try createCategory(named: name, now: now)
    }

    /// Renames a category and every template that uses it, keeping the
    /// category's identity. Returns how many templates changed.
    ///
    /// Recorded sessions are deliberately left alone: a Work Log keeps the
    /// category it was recorded with (ADR-025). Renaming onto another existing
    /// category merges the two into that one; a case-only change is allowed.
    /// General can't be renamed.
    @discardableResult
    public func renameCategory(_ oldName: String, to newName: String, now: Date = Date()) throws -> Int {
        do {
            try WorkCategory.validate(newName)
        } catch {
            throw TemplateValidationError.invalidCategory(error)
        }
        try reconcileCategories(now: now)
        let target = WorkCategory.normalized(newName)
        let records = try categories()
        guard let source = records.first(where: { WorkCategory.matches($0.name, oldName) }) else {
            throw CategoryManagementError.notFound(WorkCategory.stored(oldName))
        }
        guard source.name != target else { return 0 }
        guard !WorkCategory.isDefault(source.name) else { throw CategoryManagementError.defaultCategoryRequired }
        let merge = records.first { $0 !== source && WorkCategory.matches($0.name, target) }
        let spelling = merge?.name ?? target

        let affected = try templates().filter { WorkCategory.matches($0.category, source.name) }
        let previousTemplates = affected.map { ($0, $0.category, $0.modifiedAt) }
        let previousRecord = (name: source.name, modifiedAt: source.modifiedAt)
        for template in affected where template.category != spelling {
            template.category = spelling
            template.modifiedAt = now
        }
        if merge != nil {
            context.delete(source)
        } else {
            source.name = spelling
            source.modifiedAt = now
        }
        do {
            try save()
        } catch {
            context.rollback()
            for (template, category, modifiedAt) in previousTemplates {
                template.category = category
                template.modifiedAt = modifiedAt
            }
            if source.isLive {
                source.name = previousRecord.name
                source.modifiedAt = previousRecord.modifiedAt
            }
            throw error
        }
        return previousTemplates.filter { $0.1 != spelling }.count
    }

    /// Moves every template in `source` to `destination` and returns how many
    /// moved. Both categories stay; recorded sessions and the open session
    /// keep their category.
    @discardableResult
    public func migrateCategory(_ source: String, to destination: String, now: Date = Date()) throws -> Int {
        try moveTemplates(from: source, to: destination, deletingSource: false, now: now)
    }

    /// Deletes a category.
    ///
    /// A category templates use can only be deleted with a `destination`: the
    /// templates move there in the same save, so there is never a moment when a
    /// template names a deleted category. Recorded work logs and the open
    /// session keep the name they have. General can't be deleted.
    ///
    /// Deleting a category that no longer exists does nothing and returns 0, so
    /// a repeated confirmation can't fail. Returns how many templates moved.
    @discardableResult
    public func deleteCategory(_ name: String, migratingTemplatesTo destination: String? = nil, now: Date = Date()) throws -> Int {
        guard try categories().contains(where: { WorkCategory.matches($0.name, name) }) else { return 0 }
        guard !WorkCategory.isDefault(name) else { throw CategoryManagementError.defaultCategoryRequired }
        if let destination {
            return try moveTemplates(from: name, to: destination, deletingSource: true, now: now)
        }
        let users = try templates().filter { WorkCategory.matches($0.category, name) }
        guard users.isEmpty else {
            throw CategoryManagementError.inUse(name: WorkCategory.stored(name), templateCount: users.count)
        }
        return try moveTemplates(from: name, to: WorkCategory.defaultName, deletingSource: true, now: now)
    }

    private func moveTemplates(from source: String, to destination: String, deletingSource: Bool, now: Date) throws -> Int {
        try reconcileCategories(now: now)
        let records = try categories()
        guard let sourceRecord = records.first(where: { WorkCategory.matches($0.name, source) }) else {
            throw CategoryManagementError.notFound(WorkCategory.stored(source))
        }
        guard let destinationRecord = records.first(where: { WorkCategory.matches($0.name, destination) }) else {
            throw CategoryManagementError.destinationNotFound(WorkCategory.stored(destination))
        }
        let affected = try templates().filter { WorkCategory.matches($0.category, sourceRecord.name) }
        guard destinationRecord !== sourceRecord else {
            if affected.isEmpty, !deletingSource { return 0 }
            throw CategoryManagementError.sameDestination
        }
        let previous = affected.map { ($0, $0.category, $0.modifiedAt) }
        for template in affected {
            template.category = destinationRecord.name
            template.modifiedAt = now
        }
        if deletingSource { context.delete(sourceRecord) }
        do {
            try save()
        } catch {
            // Nothing is half-moved: the store is rolled back, and so are the
            // in-memory values the rollback doesn't restore.
            context.rollback()
            for (template, category, modifiedAt) in previous {
                template.category = category
                template.modifiedAt = modifiedAt
            }
            throw error
        }
        return affected.count
    }

    /// Creates a copy of a template named “<name> Copy” (or “Copy 2”, …),
    /// placed after the original.
    @discardableResult
    public func duplicateTemplate(_ template: WorkTemplate, now: Date = Date()) throws -> WorkTemplate {
        guard template.isLive else { throw PersistenceError.itemDeleted }
        let names = Set(try templates().map { $0.name.lowercased() })
        var draft = template.draft
        let base = String(template.name.prefix(TemplateValidator.maximumNameLength - 8))
        var candidate = "\(base) Copy"
        var index = 2
        while names.contains(candidate.lowercased()) {
            candidate = "\(base) Copy \(index)"
            index += 1
        }
        draft.name = candidate
        let copy = try createTemplate(draft, now: now)
        var ordered = try templates().filter { $0.id != copy.id }
        let position = (ordered.firstIndex { $0.id == template.id } ?? ordered.count - 1) + 1
        ordered.insert(copy, at: min(position, ordered.count))
        try moveTemplates(ordered)
        return copy
    }

    /// Deletes a template. Sessions keep their snapshot and are not affected.
    ///
    /// Deleting a template that is already gone does nothing, so a repeated
    /// confirmation can't fail or touch a detached model. If saving fails, the
    /// delete is rolled back and the template stays.
    public func deleteTemplate(_ template: WorkTemplate) throws {
        guard template.isLive else { return }
        context.delete(template)
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func moveTemplates(_ ordered: [WorkTemplate]) throws {
        for (index, template) in ordered.enumerated() where template.sortOrder != index {
            template.sortOrder = index
        }
        try save()
    }

    /// Creates the default templates once. Deleting them later does not
    /// recreate them.
    public func seedDefaultTemplatesIfNeeded(defaults: UserDefaults) throws {
        let key = "didSeedDefaultTemplates"
        guard !defaults.bool(forKey: key) else { return }
        if try templates().isEmpty {
            for draft in DefaultTemplates.drafts {
                try createTemplate(draft)
            }
        }
        defaults.set(true, forKey: key)
    }

    // MARK: Migrations

    /// Replaces emoji icons stored by Calendar Time Logger 1.0 with SF Symbol
    /// names, in templates and in the template snapshots of recorded sessions.
    ///
    /// Only the icon value changes. It runs once per store (recorded in
    /// `defaults`), is safe to repeat, and is skipped while the store is
    /// unavailable so the flag is never set against a temporary store.
    @discardableResult
    public func migrateLegacyIconsIfNeeded(defaults: UserDefaults) throws -> IconMigrationResult {
        guard canRecordWork, !defaults.bool(forKey: IconMigrationResult.defaultsKey) else { return IconMigrationResult() }
        var result = IconMigrationResult()
        for template in try templates() where TemplateSymbol.needsMigration(template.icon) {
            template.icon = TemplateSymbol.displayName(template.icon)
            result.templates += 1
        }
        for session in try context.fetch(FetchDescriptor<WorkSession>()) where TemplateSymbol.needsMigration(session.templateIcon) {
            session.templateIcon = TemplateSymbol.displayName(session.templateIcon)
            result.sessions += 1
        }
        do {
            try save()
        } catch {
            context.rollback()
            throw error
        }
        defaults.set(true, forKey: IconMigrationResult.defaultsKey)
        return result
    }

    // MARK: Sessions

    /// Sessions that are still active or paused, most recent first.
    public func openSessions() throws -> [WorkSession] {
        let active = SessionState.active.rawValue
        let paused = SessionState.paused.rawValue
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.stateRawValue == active || $0.stateRawValue == paused },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func completedSessions() throws -> [WorkSession] {
        let completed = SessionState.completed.rawValue
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.stateRawValue == completed },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func session(id: UUID) -> WorkSession? {
        var descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// What `migrateLegacyIconsIfNeeded` changed.
public struct IconMigrationResult: Equatable, Sendable {
    static let defaultsKey = "migration.sfSymbolIcons.v1"
    public var templates = 0
    public var sessions = 0
    public init(templates: Int = 0, sessions: Int = 0) {
        self.templates = templates
        self.sessions = sessions
    }
}
