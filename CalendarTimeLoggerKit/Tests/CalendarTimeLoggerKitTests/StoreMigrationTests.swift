import Foundation
import SwiftData
import Testing
@testable import CalendarTimeLoggerKit

/// Opens stores written by the frozen 1.1 (V1) and 1.2 (V2) models with the
/// shipping schema, so each migration is exercised against a store that
/// genuinely lacks the newer attributes rather than against a fresh store.
@MainActor
@Suite("Store migration")
struct StoreMigrationTests {
    /// A temporary store URL, cleaned up with its journal files.
    static func makeStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ctl-migration-\(UUID().uuidString).store")
    }

    static func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
    }

    /// Writes one template and one completed session using the frozen 1.1
    /// models. The schema is built from those types directly, so the fixture is
    /// a genuine 1.1-shaped store whatever the shipping migration plan says.
    func writeLegacyStore(at url: URL, now: Date) throws {
        let schema = Schema(
            [CalendarTimeLoggerSchemaV1.WorkTemplate.self, CalendarTimeLoggerSchemaV1.WorkSession.self],
            version: Schema.Version(1, 0, 0)
        )
        let configuration = ModelConfiguration("CalendarTimeLogger", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let template = CalendarTimeLoggerSchemaV1.WorkTemplate()
        template.name = "Software Engineering"
        template.icon = "laptopcomputer"
        template.colorHex = "#0A84FF"
        template.calendarIdentifier = "work"
        template.tags = ["coding", "development"]
        template.notes = "Everything that touches the codebase"
        template.sortOrder = 3
        template.createdAt = now
        template.modifiedAt = now
        template.menuBarConfigurationData = JSONCoding.encode(
            MenuBarConfiguration(displayMode: .iconOnly, backgroundColor: HexColor(hex: "#FF453A"))
        )
        template.notificationBehaviorData = JSONCoding.encode(
            NotificationBehavior(notifyOnStart: true, reminderIntervalMinutes: 60)
        )
        context.insert(template)

        let session = CalendarTimeLoggerSchemaV1.WorkSession()
        session.templateID = template.id
        session.templateName = "Software Engineering"
        session.templateIcon = "laptopcomputer"
        session.templateColorHex = "#0A84FF"
        session.stateRawValue = SessionState.completed.rawValue
        session.startedAt = now
        session.endedAt = now.addingTimeInterval(90 * 60)
        session.pauseIntervalsData = JSONCoding.encode([
            PauseInterval(start: now.addingTimeInterval(30 * 60), end: now.addingTimeInterval(45 * 60))
        ])
        session.notes = "[10:12] Fixed the timer drift bug"
        session.tags = ["coding"]
        session.calendarEventIdentifier = "event-1"
        session.eventCalendarIdentifier = "work"
        session.calendarSyncStatusRawValue = CalendarSyncStatus.synced.rawValue
        session.calendarLastSyncedAt = now
        session.createdAt = now
        session.modifiedAt = now
        context.insert(session)

        try context.save()
    }

    @Test("A store written by 1.1 opens under the current schema with No / No, keeping everything else")
    func migratesLegacyStore() throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        let now = TestDates.date(2026, 9, 15, 10)
        try writeLegacyStore(at: url, now: now)

        let persistence = try PersistenceService.open(url: url)
        #expect(persistence.storeError == nil)
        #expect(persistence.canRecordWork)

        let template = try #require(try persistence.templates().first)
        #expect(try persistence.templates().count == 1)
        #expect(template.taskPriority == .default)
        #expect(template.isUrgent == false)
        #expect(template.isImportant == false)
        // Nothing else was reset by the migration.
        #expect(template.name == "Software Engineering")
        #expect(template.icon == "laptopcomputer")
        #expect(template.colorHex == "#0A84FF")
        #expect(template.calendarIdentifier == "work")
        #expect(template.tags == ["coding", "development"])
        #expect(template.notes == "Everything that touches the codebase")
        #expect(template.sortOrder == 3)
        #expect(template.createdAt == now)
        #expect(template.menuBarConfiguration.displayMode == .iconOnly)
        #expect(template.menuBarConfiguration.backgroundColor?.hex == "#FF453A")
        #expect(template.notificationBehavior.notifyOnStart)
        #expect(template.notificationBehavior.reminderIntervalMinutes == 60)

        let session = try #require(try persistence.completedSessions().first)
        #expect(session.taskPriority == .default)
        #expect(session.templateID == template.id)
        #expect(session.templateName == "Software Engineering")
        #expect(session.startedAt == now)
        #expect(session.endedAt == now.addingTimeInterval(90 * 60))
        #expect(session.pauses.count == 1)
        #expect(session.notes == "[10:12] Fixed the timer drift bug")
        #expect(session.tags == ["coding"])
        #expect(session.calendarSyncStatus == .synced)
        #expect(session.calendarEventIdentifier == "event-1")

        #expect(template.category == WorkCategory.defaultName)
        #expect(session.category == WorkCategory.defaultName)
        let log = WorkLog(session: session, now: session.endedAt!)
        #expect(log.activeDuration == 75 * 60)
        #expect(log.taskPriority.quadrant == .neither)
    }

    @Test("A migrated store records new work with priority, and reopens with it")
    func recordsAfterMigration() async throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        let now = TestDates.date(2026, 9, 15, 10)
        try writeLegacyStore(at: url, now: now)

        let sessionID: UUID
        let templateID: UUID
        do {
            let env = try TestEnvironment(clock: TestClock(now.addingTimeInterval(3 * 3600)),
                                          persistence: try PersistenceService.open(url: url))
            let template = try #require(try env.persistence.templates().first)
            templateID = template.id
            // The migrated template's defaults can be changed like any other.
            var draft = template.draft
            draft.taskPriority = TaskPriority(isUrgent: false, isImportant: true)
            try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)

            let started = try env.sessionService.start(template: template,
                                                       priority: TaskPriority(isUrgent: true, isImportant: true))
            sessionID = started.id
            env.clock.advance(minutes: 25)
            try await env.sessionService.finish()
        }

        // Reopen the same file, as a relaunch would.
        let reopened = try PersistenceService.open(url: url)
        #expect(try reopened.templates().first { $0.id == templateID }?.taskPriority
                == TaskPriority(isUrgent: false, isImportant: true))
        let sessions = try reopened.completedSessions()
        #expect(sessions.count == 2)
        let recorded = try #require(sessions.first { $0.id == sessionID })
        #expect(recorded.taskPriority == TaskPriority(isUrgent: true, isImportant: true))
        // The session recorded by 1.1 is still there, unchanged.
        #expect(sessions.contains { $0.startedAt == now && $0.taskPriority == .default })
    }

    /// Writes two templates and a completed session using the frozen 1.2 models,
    /// which have task priority but no category.
    func writeV2Store(at url: URL, now: Date) throws -> (templateID: UUID, sessionID: UUID) {
        let schema = Schema(
            [CalendarTimeLoggerSchemaV2.WorkTemplate.self, CalendarTimeLoggerSchemaV2.WorkSession.self],
            version: Schema.Version(2, 0, 0)
        )
        let configuration = ModelConfiguration("CalendarTimeLogger", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let template = CalendarTimeLoggerSchemaV2.WorkTemplate()
        template.name = "Software Engineering"
        template.icon = "laptopcomputer"
        template.tags = ["coding"]
        template.isUrgent = true
        template.isImportant = true
        template.sortOrder = 0
        template.createdAt = now
        template.menuBarConfigurationData = JSONCoding.encode(MenuBarConfiguration(displayMode: .iconAndDuration))
        context.insert(template)

        let study = CalendarTimeLoggerSchemaV2.WorkTemplate()
        study.name = "Study"
        study.icon = "book"
        study.sortOrder = 1
        context.insert(study)

        let session = CalendarTimeLoggerSchemaV2.WorkSession()
        session.templateID = template.id
        session.templateName = "Software Engineering"
        session.templateIcon = "laptopcomputer"
        session.stateRawValue = SessionState.completed.rawValue
        session.startedAt = now
        session.endedAt = now.addingTimeInterval(60 * 60)
        session.notes = "Shipped the migration"
        session.tags = ["coding"]
        session.isUrgent = false
        session.isImportant = true
        session.calendarEventIdentifier = "event-2"
        session.calendarSyncStatusRawValue = CalendarSyncStatus.synced.rawValue
        context.insert(session)

        try context.save()
        return (template.id, session.id)
    }

    @Test("A store written by 1.2 opens with every template and work log in General, keeping priority and everything else")
    func migratesV2Store() throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        let now = TestDates.date(2026, 9, 16, 9)
        let ids = try writeV2Store(at: url, now: now)

        let persistence = try PersistenceService.open(url: url)
        #expect(persistence.storeError == nil)
        let templates = try persistence.templates()
        #expect(templates.map(\.name) == ["Software Engineering", "Study"])
        #expect(templates.allSatisfy { $0.category == WorkCategory.defaultName })
        let template = try #require(templates.first { $0.id == ids.templateID })
        #expect(template.taskPriority == TaskPriority(isUrgent: true, isImportant: true))
        #expect(template.tags == ["coding"])
        #expect(template.menuBarConfiguration.displayMode == .iconAndDuration)

        let sessions = try persistence.completedSessions()
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == ids.sessionID)
        #expect(session.category == WorkCategory.defaultName)
        #expect(session.taskPriority == TaskPriority(isUrgent: false, isImportant: true))
        #expect(session.notes == "Shipped the migration")
        #expect(session.calendarEventIdentifier == "event-2")
        #expect(session.endedAt == now.addingTimeInterval(3600))
        #expect(WorkLog(session: session).category == WorkCategory.defaultName)
    }

    @Test("After migrating a 1.2 store, templates still require a category and new sessions keep theirs across relaunch")
    func recordsCategoryAfterV2Migration() async throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        let now = TestDates.date(2026, 9, 16, 9)
        let ids = try writeV2Store(at: url, now: now)

        let sessionID: UUID
        do {
            let env = try TestEnvironment(clock: TestClock(now.addingTimeInterval(2 * 3600)),
                                          persistence: try PersistenceService.open(url: url))
            let template = try #require(env.persistence.template(id: ids.templateID))
            var draft = template.draft
            draft.category = ""
            #expect(throws: TemplateValidationError.invalidCategory(.empty)) { try env.persistence.updateTemplate(template, with: draft) }
            draft.category = "Development"
            try env.persistence.updateTemplate(template, with: draft, now: env.clock.now)

            let started = try env.sessionService.start(template: template)
            sessionID = started.id
            env.clock.advance(minutes: 50)
            try await env.sessionService.finish()
        }

        let reopened = try PersistenceService.open(url: url)
        #expect(reopened.template(id: ids.templateID)?.category == "Development")
        #expect(reopened.session(id: sessionID)?.category == "Development")
        // The 1.2 work log stays in General; the template change didn't touch it.
        #expect(reopened.session(id: ids.sessionID)?.category == WorkCategory.defaultName)
    }

    /// Writes templates and work logs using the frozen 1.3 models, which have
    /// categories as names but no stored category list.
    func writeV3Store(at url: URL, now: Date) throws -> (templateID: UUID, sessionID: UUID, activeID: UUID) {
        let schema = Schema(
            [CalendarTimeLoggerSchemaV3.WorkTemplate.self, CalendarTimeLoggerSchemaV3.WorkSession.self],
            version: Schema.Version(3, 0, 0)
        )
        let configuration = ModelConfiguration("CalendarTimeLogger", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let grooming = CalendarTimeLoggerSchemaV3.WorkTemplate()
        grooming.name = "Grooming"
        grooming.icon = "heart"
        grooming.category = "Grooming"
        grooming.isImportant = true
        grooming.sortOrder = 0
        context.insert(grooming)

        let chill = CalendarTimeLoggerSchemaV3.WorkTemplate()
        chill.name = "Chill"
        chill.icon = "pencil"
        chill.category = "General"
        chill.sortOrder = 1
        context.insert(chill)

        let session = CalendarTimeLoggerSchemaV3.WorkSession()
        session.templateID = grooming.id
        session.templateName = "Grooming"
        session.templateIcon = "heart"
        session.category = "Old Name"
        session.stateRawValue = SessionState.completed.rawValue
        session.startedAt = now
        session.endedAt = now.addingTimeInterval(3600)
        session.isUrgent = true
        session.calendarEventIdentifier = "event-3"
        session.calendarSyncStatusRawValue = CalendarSyncStatus.synced.rawValue
        context.insert(session)

        let active = CalendarTimeLoggerSchemaV3.WorkSession()
        active.templateID = chill.id
        active.templateName = "Chill"
        active.templateIcon = "pencil"
        active.category = "General"
        active.stateRawValue = SessionState.paused.rawValue
        active.startedAt = now.addingTimeInterval(7200)
        context.insert(active)

        try context.save()
        return (grooming.id, session.id, active.id)
    }

    @Test("A store written by 1.3 opens with a category list of the built-ins plus template categories, changing no template or work log")
    func migratesV3Store() throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        let now = TestDates.date(2026, 9, 17, 9)
        let ids = try writeV3Store(at: url, now: now)

        let persistence = try PersistenceService.open(url: url)
        #expect(persistence.storeError == nil)
        #expect(try persistence.availableCategories() == WorkCategory.builtIn + ["Grooming"])
        // Work log categories don't become list entries.
        #expect(try !persistence.availableCategories().contains("Old Name"))

        let template = try #require(persistence.template(id: ids.templateID))
        #expect(template.category == "Grooming")
        #expect(template.taskPriority == TaskPriority(isUrgent: false, isImportant: true))
        let session = try #require(persistence.session(id: ids.sessionID))
        #expect(session.category == "Old Name")
        #expect(session.taskPriority == TaskPriority(isUrgent: true, isImportant: false))
        #expect(session.endedAt == now.addingTimeInterval(3600))
        #expect(session.calendarEventIdentifier == "event-3")
        #expect(try persistence.openSessions().map(\.id) == [ids.activeID])

        // Deleting after migration sticks across relaunch, and nothing is reseeded.
        try persistence.deleteCategory("Grooming", migratingTemplatesTo: "General")
        try persistence.deleteCategory("Design")
        let reopened = try PersistenceService.open(url: url)
        #expect(try reopened.availableCategories() == ["Development", "Education", "Research", "Content", "General"])
        #expect(reopened.template(id: ids.templateID)?.category == "General")
        #expect(reopened.session(id: ids.sessionID)?.category == "Old Name")
    }

    @Test("Opening a store the current schema already wrote is a no-op")
    func reopensCurrentStore() throws {
        let url = Self.makeStoreURL()
        defer { Self.remove(url) }
        do {
            let persistence = try PersistenceService.open(url: url)
            try persistence.createTemplate(WorkTemplateDraft(name: "Research", icon: "flask",
                                                             taskPriority: TaskPriority(isUrgent: true, isImportant: false)))
        }
        let reopened = try PersistenceService.open(url: url)
        #expect(reopened.storeError == nil)
        #expect(try reopened.templates().map(\.name) == ["Research"])
        #expect(try reopened.templates().first?.taskPriority == TaskPriority(isUrgent: true, isImportant: false))
    }
}
