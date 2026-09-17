import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

/// The stored category list: creating, renaming, migrating, and deleting
/// categories without rewriting recorded work (ADR-027).
@MainActor
@Suite("Category management")
struct CategoryManagementTests {
    @Test("A new store lists the built-in categories once, and reconciling again changes nothing")
    func seeding() throws {
        let env = try TestEnvironment()
        #expect(try env.persistence.availableCategories() == WorkCategory.builtIn)
        #expect(try env.persistence.reconcileCategories() == 0)
        #expect(try env.persistence.categories().count == WorkCategory.builtIn.count)
    }

    // MARK: Creating

    @Test("Creating a category tidies the name, keeps it while unused, and refuses blanks and duplicates")
    func create() throws {
        let env = try TestEnvironment()
        let record = try env.persistence.createCategory(named: "  Client   Work ")
        #expect(record.name == "Client Work")
        #expect(try env.persistence.availableCategories().contains("Client Work"))
        #expect(try env.persistence.categoryUsage().first { $0.name == "Client Work" }?.templateCount == 0)

        #expect(throws: CategoryValidationError.empty) { try env.persistence.createCategory(named: "   ") }
        #expect(throws: CategoryValidationError.duplicate("Client Work")) { try env.persistence.createCategory(named: "client work") }
        #expect(throws: CategoryValidationError.duplicate("Research")) { try env.persistence.createCategory(named: "RESEARCH") }
        #expect(throws: CategoryValidationError.tooLong(max: WorkCategory.maximumLength)) {
            try env.persistence.createCategory(named: String(repeating: "x", count: WorkCategory.maximumLength + 1))
        }
        // A rapid second Add can't create a twin.
        #expect(try env.persistence.categories().filter { WorkCategory.matches($0.name, "Client Work") }.count == 1)
        // Typing a name in place selects an existing category instead of failing.
        #expect(try env.persistence.categoryNamed("client work").id == record.id)
    }

    @Test("A category created before any template uses it survives a relaunch of the store")
    func createPersists() throws {
        let url = StoreMigrationTests.makeStoreURL()
        defer { StoreMigrationTests.remove(url) }
        let id: UUID
        do {
            let persistence = try PersistenceService.open(url: url)
            id = try persistence.createCategory(named: "Operations").id
        }
        let reopened = try PersistenceService.open(url: url)
        #expect(reopened.category(id: id)?.name == "Operations")
        #expect(try reopened.availableCategories().filter { $0 == "Operations" }.count == 1)
    }

    // MARK: Renaming (Scenario E)

    @Test("Scenario E: renaming keeps the category's identity, updates its templates, and leaves work logs alone")
    func renameKeepsIdentity() async throws {
        let env = try TestEnvironment()
        let work = try env.persistence.createCategory(named: "Work")
        let a = try env.makeTemplate(name: "Planning", category: "Work")
        let b = try env.makeTemplate(name: "Reviews", icon: "flask", category: "work")
        try env.sessionService.start(template: a)
        env.clock.advance(minutes: 30)
        let recorded = try await env.sessionService.finish()

        let changed = try env.persistence.renameCategory("Work", to: "Professional Work")
        #expect(changed == 2)
        #expect(env.persistence.category(id: work.id)?.name == "Professional Work")
        #expect(a.category == "Professional Work")
        #expect(b.category == "Professional Work")
        #expect(try !env.persistence.availableCategories().contains("Work"))
        // History keeps the name it was recorded with.
        #expect(env.persistence.session(id: recorded.log.id)?.category == "Work")
        // Future sessions use the new name.
        let next = try env.sessionService.start(template: b)
        #expect(next.category == "Professional Work")
    }

    @Test("Renaming onto an existing category merges into it; General can't be renamed")
    func renameMergesAndProtectsGeneral() throws {
        let env = try TestEnvironment()
        let research = try #require(try env.persistence.categories().first { $0.name == "Research" })
        try env.persistence.createCategory(named: "Investigation")
        let template = try env.makeTemplate(name: "Papers", icon: "flask", category: "Investigation")
        #expect(try env.persistence.renameCategory("Investigation", to: "research") == 1)
        #expect(template.category == "Research")
        #expect(try env.persistence.categories().filter { $0.name == "Research" }.map(\.id) == [research.id])
        #expect(try !env.persistence.availableCategories().contains("Investigation"))

        #expect(throws: CategoryManagementError.defaultCategoryRequired) { try env.persistence.renameCategory("General", to: "Misc") }
        #expect(throws: CategoryManagementError.notFound("Nope")) { try env.persistence.renameCategory("Nope", to: "Other") }
        #expect(try env.persistence.renameCategory("Research", to: "Research") == 0)
    }

    // MARK: Deleting and migrating (Scenarios A–D)

    @Test("Scenario A: an unused category is deleted, and deleting it again does nothing")
    func deleteUnused() throws {
        let env = try TestEnvironment()
        #expect(try env.persistence.deleteCategory("Design") == 0)
        #expect(try !env.persistence.availableCategories().contains("Design"))
        #expect(try env.persistence.deleteCategory("Design") == 0)
        // A deleted built-in isn't brought back by reconciling.
        try env.persistence.reconcileCategories()
        #expect(try !env.persistence.availableCategories().contains("Design"))
    }

    @Test("Scenario B: a category used by one template can't be deleted until its template moves")
    func deleteUsedByOne() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(name: "Mockups", icon: "paintpalette", category: "Design")
        #expect(throws: CategoryManagementError.inUse(name: "Design", templateCount: 1)) { try env.persistence.deleteCategory("Design") }
        #expect(template.category == "Design")
        #expect(try env.persistence.availableCategories().contains("Design"))

        #expect(try env.persistence.deleteCategory("Design", migratingTemplatesTo: "Content") == 1)
        #expect(template.category == "Content")
        #expect(try !env.persistence.availableCategories().contains("Design"))
    }

    @Test("Scenario C: migrating moves every template, then the source can be deleted")
    func migrateMany() throws {
        let env = try TestEnvironment()
        try env.persistence.createCategory(named: "Work")
        let templates = try (1...3).map { try env.makeTemplate(name: "Task \($0)", category: "Work") }
        let study = try env.makeTemplate(name: "Study", icon: "book", category: "Education")

        #expect(throws: CategoryManagementError.sameDestination) { try env.persistence.migrateCategory("Work", to: "work") }
        #expect(throws: CategoryManagementError.destinationNotFound("Nowhere")) { try env.persistence.migrateCategory("Work", to: "Nowhere") }
        #expect(templates.allSatisfy { $0.category == "Work" })

        #expect(try env.persistence.migrateCategory("Work", to: "General") == 3)
        #expect(templates.allSatisfy { $0.category == "General" })
        #expect(study.category == "Education")
        // The source stays until it is deleted, and is now unused.
        #expect(try env.persistence.categoryUsage().first { $0.name == "Work" }?.templateCount == 0)
        #expect(try env.persistence.deleteCategory("Work") == 0)
        #expect(try !env.persistence.availableCategories().contains("Work"))
        // Migrating again is harmless.
        #expect(try env.persistence.migrateCategory("General", to: "Education") == 3)
        #expect(throws: CategoryManagementError.defaultCategoryRequired) { try env.persistence.deleteCategory("General") }
    }

    @Test("Scenario D: a category with work logs but no templates is deleted; the work logs, analytics, and new sessions stay consistent")
    func deleteWithHistory() async throws {
        let env = try TestEnvironment()
        try env.persistence.createCategory(named: "Work")
        let template = try env.makeTemplate(name: "Planning", category: "Work",
                                            priority: TaskPriority(isUrgent: true, isImportant: false))
        try env.sessionService.start(template: template)
        env.clock.advance(minutes: 45)
        let recorded = try await env.sessionService.finish()
        try env.persistence.migrateCategory("Work", to: "Research")

        let usage = try #require(try env.persistence.categoryUsage().first { $0.name == "Work" })
        #expect(usage.templateCount == 0)
        #expect(usage.workLogCount == 1)
        #expect(try env.persistence.deleteCategory("Work") == 0)

        let log = try #require(env.persistence.session(id: recorded.log.id))
        #expect(log.category == "Work")
        #expect(log.taskPriority == TaskPriority(isUrgent: true, isImportant: false))
        #expect(log.endedAt == recorded.log.endedAt)
        let totals = WorkAnalytics.categoryTotals(try env.persistence.completedSessions().map { WorkLog(session: $0) })
        #expect(totals.map(\.name) == ["Work"])
        #expect(totals.first?.duration == TimeInterval(45 * 60))
        // The template now starts sessions in its migrated category.
        env.clock.advance(minutes: 5)
        #expect(try env.sessionService.start(template: template).category == "Research")
        // The deleted name doesn't come back from history.
        #expect(try !env.persistence.availableCategories().contains("Work"))
    }

    @Test("Deleting the open session's category leaves the session running with its category")
    func deleteDuringActiveSession() async throws {
        let env = try TestEnvironment()
        try env.persistence.createCategory(named: "Work")
        let template = try env.makeTemplate(name: "Planning", category: "Work")
        let session = try env.sessionService.start(template: template)
        #expect(try env.persistence.categoryUsage().first { $0.name == "Work" }?.isUsedByOpenSession == true)

        #expect(try env.persistence.deleteCategory("Work", migratingTemplatesTo: "General") == 1)
        #expect(env.sessionService.activeSession?.id == session.id)
        #expect(session.category == "Work")
        try env.sessionService.updateTaskPriority(TaskPriority(isUrgent: true, isImportant: true))
        #expect(session.category == "Work")
        env.clock.advance(minutes: 20)
        let completion = try await env.sessionService.finish()
        #expect(completion.log.category == "Work")
        #expect(template.category == "General")
    }

    // MARK: Scenario F

    @Test("Scenario F: after a migrate and delete, reopening the store shows the same categories, templates, and work logs")
    func survivesRelaunch() async throws {
        let url = StoreMigrationTests.makeStoreURL()
        defer { StoreMigrationTests.remove(url) }
        let clock = TestClock()
        let ids: (template: UUID, session: UUID, renamed: UUID)
        do {
            let env = try TestEnvironment(clock: clock, persistence: try PersistenceService.open(url: url))
            try env.persistence.createCategory(named: "Work")
            let renamed = try env.persistence.createCategory(named: "Ops")
            let template = try env.makeTemplate(name: "Planning", category: "Work")
            try env.sessionService.start(template: template)
            clock.advance(minutes: 30)
            let completion = try await env.sessionService.finish()
            try env.persistence.renameCategory("Ops", to: "Operations")
            try env.persistence.deleteCategory("Work", migratingTemplatesTo: "Operations")
            try env.persistence.deleteCategory("Design")
            ids = (template.id, completion.log.id, renamed.id)
        }
        let reopened = try PersistenceService.open(url: url)
        let names = try reopened.availableCategories()
        #expect(names == ["Development", "Education", "Research", "Content", "General", "Operations"])
        #expect(reopened.category(id: ids.renamed)?.name == "Operations")
        #expect(reopened.template(id: ids.template)?.category == "Operations")
        #expect(reopened.session(id: ids.session)?.category == "Work")
        #expect(try reopened.reconcileCategories() == 0)
    }

    @Test("Templates never point at a category the list doesn't have")
    func templatesAlwaysListed() throws {
        let env = try TestEnvironment()
        let template = try env.makeTemplate(name: "Side Project", category: "Hobby")
        #expect(try env.persistence.availableCategories().contains("Hobby"))
        var draft = template.draft
        draft.category = "Volunteering"
        try env.persistence.updateTemplate(template, with: draft)
        #expect(try env.persistence.availableCategories().contains("Volunteering"))
        // The old custom category stays until it is deleted.
        #expect(try env.persistence.availableCategories().contains("Hobby"))
    }

    @Test("Duplicate records that differ only by case are merged into the oldest")
    func mergesDuplicates() throws {
        let env = try TestEnvironment()
        let first = try env.persistence.createCategory(named: "Operations", now: TestDates.date(2026, 1, 1))
        env.persistence.context.insert(WorkCategoryRecord(name: "operations", createdAt: TestDates.date(2026, 2, 1)))
        try env.persistence.save()
        #expect(try env.persistence.reconcileCategories() == 1)
        #expect(try env.persistence.categories().filter { WorkCategory.matches($0.name, "operations") }.map(\.id) == [first.id])
    }
}
