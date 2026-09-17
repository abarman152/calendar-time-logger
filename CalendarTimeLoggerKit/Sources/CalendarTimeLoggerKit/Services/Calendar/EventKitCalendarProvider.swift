import EventKit
import Foundation

/// EventKit implementation of `CalendarProviding`.
@MainActor
public final class EventKitCalendarProvider: CalendarProviding {
    private var store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    /// Called when the Calendar database changes outside the app.
    public var onStoreChanged: (() -> Void)?

    public init() {
        observeStore()
    }

    private func observeStore() {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onStoreChanged?() }
        }
    }

    public var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    public func requestFullAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToEvents()
        if granted {
            // A fresh store reliably reflects newly granted access.
            store = EKEventStore()
            observeStore()
        }
        return granted
    }

    public func calendars() -> [CalendarInfo] {
        guard authorization == .fullAccess else { return [] }
        return store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "Other",
                    color: calendar.cgColor.flatMap(Self.rgb),
                    allowsModifications: calendar.allowsContentModifications
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func systemDefaultCalendarIdentifier() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    public func event(withIdentifier identifier: String) -> CalendarEventRecord? {
        store.event(withIdentifier: identifier).map(Self.record)
    }

    public func saveEvent(_ draft: CalendarEventDraft, existingIdentifier: String?) throws -> CalendarEventRecord {
        guard let calendar = store.calendar(withIdentifier: draft.calendarIdentifier) else {
            throw CalendarProviderError.calendarNotFound(draft.calendarIdentifier)
        }
        guard calendar.allowsContentModifications else {
            throw CalendarProviderError.calendarReadOnly(calendar.title)
        }
        let event: EKEvent
        if let existingIdentifier {
            guard let existing = store.event(withIdentifier: existingIdentifier) else {
                throw CalendarProviderError.eventNotFound(existingIdentifier)
            }
            event = existing
        } else {
            event = EKEvent(eventStore: store)
        }
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = false
        event.notes = draft.notes
        event.url = draft.url
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarProviderError.operationFailed(error.localizedDescription)
        }
        return Self.record(event)
    }

    public func removeEvent(withIdentifier identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarProviderError.eventNotFound(identifier)
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarProviderError.operationFailed(error.localizedDescription)
        }
    }

    public func events(in interval: DateInterval, calendarIdentifiers: [String]?) -> [CalendarEventRecord] {
        guard authorization == .fullAccess else { return [] }
        let calendars = calendarIdentifiers?.compactMap { store.calendar(withIdentifier: $0) }
        if let calendars, calendars.isEmpty { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).map(Self.record)
    }

    private static func record(_ event: EKEvent) -> CalendarEventRecord {
        CalendarEventRecord(
            identifier: event.eventIdentifier ?? "",
            calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            url: event.url
        )
    }

    private static func rgb(_ color: CGColor) -> HexColor? {
        guard let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        return HexColor(red: components[0], green: components[1], blue: components[2])
    }
}
