import Foundation
@testable import CalendarTimeLoggerKit

/// A controllable clock for deterministic tests.
@MainActor
final class TestClock {
    var now: Date

    init(_ now: Date = TestDates.date(2026, 9, 15, 10, 0)) {
        self.now = now
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }

    func set(_ hour: Int, _ minute: Int) {
        let calendar = TestDates.calendar
        now = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
    }
}

enum TestDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

/// In-memory stand-in for EventKit.
@MainActor
final class MockCalendarProvider: CalendarProviding {
    var authorization: CalendarAuthorization = .fullAccess
    var authorizationAfterRequest: CalendarAuthorization = .fullAccess
    var requestCount = 0
    var calendarList: [CalendarInfo] = [
        CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", color: HexColor(hex: "#0A84FF"), allowsModifications: true),
        CalendarInfo(id: "personal", title: "Personal", sourceTitle: "iCloud", color: HexColor(hex: "#30D158"), allowsModifications: true),
        CalendarInfo(id: "university", title: "University", sourceTitle: "Google", color: nil, allowsModifications: true),
        CalendarInfo(id: "holidays", title: "Holidays", sourceTitle: "Other", color: nil, allowsModifications: false)
    ]
    var systemDefault: String? = "personal"
    var events: [String: (record: CalendarEventRecord, notes: String)] = [:]
    var saveError: CalendarProviderError?
    var saveCalls: [(draft: CalendarEventDraft, existing: String?)] = []
    var removedIdentifiers: [String] = []
    private var nextID = 1

    /// Runs while the (simulated) permission prompt is up, before access is decided.
    var onRequestFullAccess: (() -> Void)?

    func requestFullAccess() async throws -> Bool {
        requestCount += 1
        onRequestFullAccess?()
        authorization = authorizationAfterRequest
        return authorization == .fullAccess
    }

    func calendars() -> [CalendarInfo] { authorization == .fullAccess ? calendarList : [] }

    func systemDefaultCalendarIdentifier() -> String? { systemDefault }

    func event(withIdentifier identifier: String) -> CalendarEventRecord? { events[identifier]?.record }

    func saveEvent(_ draft: CalendarEventDraft, existingIdentifier: String?) throws -> CalendarEventRecord {
        saveCalls.append((draft, existingIdentifier))
        if let saveError { throw saveError }
        guard let calendar = calendarList.first(where: { $0.id == draft.calendarIdentifier }) else {
            throw CalendarProviderError.calendarNotFound(draft.calendarIdentifier)
        }
        guard calendar.allowsModifications else { throw CalendarProviderError.calendarReadOnly(calendar.title) }
        let identifier: String
        if let existingIdentifier {
            guard events[existingIdentifier] != nil else { throw CalendarProviderError.eventNotFound(existingIdentifier) }
            identifier = existingIdentifier
        } else {
            identifier = "event-\(nextID)"
            nextID += 1
        }
        let record = CalendarEventRecord(identifier: identifier, calendarIdentifier: draft.calendarIdentifier,
                                         title: draft.title, startDate: draft.startDate, endDate: draft.endDate, url: draft.url)
        events[identifier] = (record, draft.notes)
        return record
    }

    func removeEvent(withIdentifier identifier: String) throws {
        guard events.removeValue(forKey: identifier) != nil else { throw CalendarProviderError.eventNotFound(identifier) }
        removedIdentifiers.append(identifier)
    }

    func events(in interval: DateInterval, calendarIdentifiers: [String]?) -> [CalendarEventRecord] {
        events.values.map(\.record).filter { record in
            record.startDate < interval.end && record.endDate > interval.start
                && (calendarIdentifiers?.contains(record.calendarIdentifier) ?? true)
        }
    }

    /// Simulates Calendar assigning a new identifier to an existing event.
    func reassignIdentifier(_ old: String, to new: String) {
        guard let entry = events.removeValue(forKey: old) else { return }
        let r = entry.record
        events[new] = (CalendarEventRecord(identifier: new, calendarIdentifier: r.calendarIdentifier, title: r.title,
                                           startDate: r.startDate, endDate: r.endDate, url: r.url), entry.notes)
    }

    /// Adds an event the app does not own.
    func insertForeignEvent(identifier: String, url: URL? = nil) {
        events[identifier] = (CalendarEventRecord(identifier: identifier, calendarIdentifier: "work", title: "Dentist",
                                                  startDate: .now, endDate: .now, url: url), "")
    }
}

/// In-memory stand-in for UserNotifications.
@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    var status: NotificationAuthorization = .authorized
    var statusAfterRequest: NotificationAuthorization = .authorized
    var requestCount = 0
    var added: [NotificationRequest] = []
    var removed: [String] = []

    func authorizationStatus() async -> NotificationAuthorization { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = statusAfterRequest
        return status == .authorized
    }

    func add(_ request: NotificationRequest) async throws { added.append(request) }

    func removePendingRequests(withIdentifiers identifiers: [String]) { removed.append(contentsOf: identifiers) }
}

/// Wires the real services to mocks and an in-memory store.
@MainActor
final class TestEnvironment {
    let clock: TestClock
    let defaults: UserDefaults
    let settings: SettingsStore
    let persistence: PersistenceService
    let calendarProvider = MockCalendarProvider()
    let notificationScheduler = MockNotificationScheduler()
    let calendarService: CalendarService
    let notificationService: NotificationService
    private(set) var sessionService: SessionService

    init(clock: TestClock = TestClock(), persistence: PersistenceService? = nil) throws {
        self.clock = clock
        let suite = "CalendarTimeLoggerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = SettingsStore(defaults: defaults)
        self.persistence = try persistence ?? PersistenceService.inMemory()
        let settings = self.settings
        calendarService = CalendarService(
            provider: calendarProvider,
            persistence: self.persistence,
            configuration: { settings.calendarConfiguration },
            now: { clock.now }
        )
        notificationService = NotificationService(
            scheduler: notificationScheduler,
            preferences: { settings.notificationPreferences },
            now: { clock.now }
        )
        sessionService = SessionService(
            persistence: self.persistence,
            calendarService: calendarService,
            notificationService: notificationService,
            now: { clock.now }
        )
    }

    /// Simulates relaunching the app against the same store.
    func relaunch() {
        let clock = self.clock
        sessionService = SessionService(
            persistence: persistence,
            calendarService: calendarService,
            notificationService: notificationService,
            now: { clock.now }
        )
    }

    @discardableResult
    func makeTemplate(
        name: String = "Software Engineering",
        icon: String = "laptopcomputer",
        category: String = "Development",
        calendarIdentifier: String? = nil,
        tags: [String] = ["coding", "development"],
        priority: TaskPriority = .default,
        behavior: NotificationBehavior = .default,
        menuBar: MenuBarConfiguration = .default
    ) throws -> WorkTemplate {
        try persistence.createTemplate(WorkTemplateDraft(
            name: name, icon: icon, color: TemplatePalette.colors[0].color, category: category,
            calendarIdentifier: calendarIdentifier,
            tags: tags, taskPriority: priority, notificationBehavior: behavior, menuBarConfiguration: menuBar
        ), now: clock.now)
    }
}
