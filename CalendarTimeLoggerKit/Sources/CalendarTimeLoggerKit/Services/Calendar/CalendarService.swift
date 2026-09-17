import Foundation
import Observation

public enum CalendarSyncError: Error, Equatable, LocalizedError, Sendable {
    case syncDisabled
    case accessNotGranted(CalendarAuthorization)
    case noCalendarAvailable
    case calendarNotFound
    case calendarReadOnly(String)
    case eventNotOwned
    case sessionNotCompleted
    case saveFailed(String)
    case removeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .syncDisabled: "Calendar sync is turned off."
        case .accessNotGranted(.writeOnly): "Calendar Time Logger has “Add Events Only” access."
        case .accessNotGranted: "Calendar Time Logger doesn’t have access to your calendars."
        case .noCalendarAvailable: "No calendar is available for new events."
        case .calendarNotFound: "The selected calendar no longer exists."
        case .calendarReadOnly(let name): "The calendar “\(name)” is read-only."
        case .eventNotOwned: "That Calendar event wasn’t created by Calendar Time Logger, so it wasn’t changed."
        case .sessionNotCompleted: "Only completed sessions can be added to Calendar."
        case .saveFailed: "The Calendar event couldn’t be saved."
        case .removeFailed: "The Calendar event couldn’t be removed."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .syncDisabled: "Turn on Calendar sync in Settings › Calendar."
        case .accessNotGranted(.notDetermined): "Connect Apple Calendar in Settings › Calendar."
        case .accessNotGranted: "Allow full Calendar access in System Settings › Privacy & Security › Calendars, then retry."
        case .noCalendarAvailable: "Add a calendar in the Calendar app, then retry."
        case .calendarNotFound: "Choose another calendar for this template or in Settings › Calendar, then retry."
        case .calendarReadOnly: "Choose a calendar you can edit, then retry."
        case .eventNotOwned: "Your work log is unchanged. Retry to create a new event for it."
        case .sessionNotCompleted: nil
        case .saveFailed(let reason), .removeFailed(let reason): "\(reason) Your work log is saved; you can retry later."
        }
    }

    /// One-line message stored on the session and shown in Work Logs.
    public var storedMessage: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }
}

public enum CalendarSyncOutcome: Equatable, Sendable {
    case created(eventIdentifier: String)
    case updated(eventIdentifier: String)
    /// Nothing was written because sync is off.
    case skipped
    case failed(CalendarSyncError)

    public var succeeded: Bool {
        switch self {
        case .created, .updated: true
        case .skipped, .failed: false
        }
    }
}

/// Keeps app-owned Calendar events in sync with completed sessions.
///
/// The session is always the source of truth: every method records the result
/// on the session and never throws away work because Calendar failed.
@MainActor
@Observable
public final class CalendarService {
    @ObservationIgnored private let provider: CalendarProviding
    @ObservationIgnored private let persistence: PersistenceService
    @ObservationIgnored private let configuration: () -> CalendarConfiguration
    @ObservationIgnored private let now: () -> Date

    public private(set) var authorization: CalendarAuthorization
    public private(set) var availableCalendars: [CalendarInfo] = []

    public init(
        provider: CalendarProviding,
        persistence: PersistenceService,
        configuration: @escaping () -> CalendarConfiguration,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.persistence = persistence
        self.configuration = configuration
        self.now = now
        self.authorization = provider.authorization
        refresh()
    }

    // MARK: Access and discovery

    public func refresh() {
        authorization = provider.authorization
        availableCalendars = authorization == .fullAccess ? provider.calendars() : []
    }

    /// Requests full access only when it has never been requested.
    @discardableResult
    public func requestAccess() async -> CalendarAuthorization {
        if provider.authorization == .notDetermined {
            _ = try? await provider.requestFullAccess()
        }
        refresh()
        return authorization
    }

    public var writableCalendars: [CalendarInfo] { availableCalendars.filter(\.allowsModifications) }

    public func calendar(withIdentifier identifier: String?) -> CalendarInfo? {
        guard let identifier else { return nil }
        return availableCalendars.first { $0.id == identifier }
    }

    public var systemDefaultCalendar: CalendarInfo? {
        calendar(withIdentifier: provider.systemDefaultCalendarIdentifier())
    }

    /// Resolution order: session override → template → global default → system default.
    public func resolvedCalendarIdentifier(for session: WorkSession) -> String? {
        let template = persistence.template(id: session.templateID)
        return session.calendarIdentifier
            ?? template?.calendarIdentifier
            ?? configuration().defaultCalendarIdentifier
            ?? provider.systemDefaultCalendarIdentifier()
    }

    // MARK: Event content

    public func makeDraft(for session: WorkSession, calendarIdentifier: String) -> CalendarEventDraft? {
        guard let endedAt = session.endedAt else { return nil }
        let log = WorkLog(session: session, now: endedAt)
        let configuration = configuration()
        // The session's timestamps are passed through unchanged unless the user
        // chose minute-aligned events; the session itself is never modified.
        let event = configuration.eventTiming.eventInterval(for: WorkInterval(start: session.startedAt, end: endedAt))
        return CalendarEventDraft(
            title: session.templateName,
            startDate: event.start,
            endDate: event.end,
            notes: Self.eventNotes(for: log, configuration: configuration),
            url: session.calendarOwnershipURL,
            calendarIdentifier: calendarIdentifier
        )
    }

    /// Human-readable notes. Internal identifiers stay in the event URL.
    public static func eventNotes(for log: WorkLog, configuration: CalendarConfiguration) -> String {
        var lines = ["Recorded with Calendar Time Logger", "", "Template: \(log.templateName)", "Category: \(log.category)"]
        lines.append("Active work: \(DurationFormatting.short(log.activeDuration))")
        // Priority lives in the notes, not the title: event titles stay short
        // and Apple Calendar has no field for it (ADR-022).
        lines.append("Urgent: \(TaskPriority.yesNo(log.isUrgent)) · Important: \(TaskPriority.yesNo(log.isImportant))")
        if log.pausedDuration >= 60 {
            lines.append("Paused: \(DurationFormatting.short(log.pausedDuration))")
        }
        if configuration.includesTags, !log.tags.isEmpty {
            lines.append("")
            lines.append("Tags: \(TagParsing.display(log.tags))")
        }
        let notes = log.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if configuration.includesNotes, !notes.isEmpty {
            lines.append("")
            lines.append("Notes:")
            lines.append(notes)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Synchronization

    /// Creates or updates the app-owned event for a completed session.
    ///
    /// - Parameter requestAccessIfNeeded: ask for access when it was never
    ///   requested. Used on the first finished session, where the request has
    ///   clear context for the user.
    @discardableResult
    public func sync(_ session: WorkSession, requestAccessIfNeeded: Bool = false) async -> CalendarSyncOutcome {
        guard session.isLive else { return .skipped }
        guard session.state == .completed, session.endedAt != nil else {
            return .failed(.sessionNotCompleted)
        }
        guard configuration().isSyncEnabled else { return .skipped }

        if requestAccessIfNeeded {
            await requestAccess()
            // The work log may have been deleted while the permission prompt was up.
            guard session.isLive else { return .skipped }
        } else {
            refresh()
        }
        guard authorization == .fullAccess else {
            return record(.accessNotGranted(authorization), on: session)
        }
        guard let calendarIdentifier = resolvedCalendarIdentifier(for: session) else {
            return record(.noCalendarAvailable, on: session)
        }
        guard let calendar = calendar(withIdentifier: calendarIdentifier) else {
            return record(.calendarNotFound, on: session)
        }
        guard calendar.allowsModifications else {
            return record(.calendarReadOnly(calendar.title), on: session)
        }
        guard let draft = makeDraft(for: session, calendarIdentifier: calendarIdentifier) else {
            return .failed(.sessionNotCompleted)
        }

        // Only update an existing event after verifying this session owns it.
        // Looking it up by ownership URL as well avoids duplicates when
        // Calendar has assigned the event a new identifier.
        let existingIdentifier = ownedEvent(for: session)?.identifier

        do {
            let saved = try provider.saveEvent(draft, existingIdentifier: existingIdentifier)
            session.calendarEventIdentifier = saved.identifier
            session.eventCalendarIdentifier = saved.calendarIdentifier
            session.calendarSyncStatus = .synced
            session.calendarSyncMessage = nil
            session.calendarLastSyncedAt = now()
            try? persistence.save()
            return existingIdentifier == nil ? .created(eventIdentifier: saved.identifier) : .updated(eventIdentifier: saved.identifier)
        } catch let error as CalendarProviderError {
            return record(map(error), on: session)
        } catch {
            return record(.saveFailed(error.localizedDescription), on: session)
        }
    }

    /// Brings the times of existing app-owned events in line with the current
    /// event timing setting, and returns how many events changed.
    ///
    /// Only events this app created and that still exist are updated, and only
    /// when their times differ, so running it twice changes nothing the second
    /// time. Missing events are not recreated, sessions are never modified
    /// beyond their sync record, and events owned by nobody are never touched.
    @discardableResult
    public func applyEventTimingToExistingEvents(_ sessions: [WorkSession]) async -> (updated: Int, failed: Int) {
        refresh()
        guard configuration().isSyncEnabled, authorization == .fullAccess else { return (0, 0) }
        var updated = 0, failed = 0
        for session in sessions where session.isLive && session.state == .completed && session.calendarSyncStatus == .synced {
            guard let owned = ownedEvent(for: session),
                  let calendarIdentifier = resolvedCalendarIdentifier(for: session),
                  let draft = makeDraft(for: session, calendarIdentifier: calendarIdentifier) else { continue }
            guard owned.startDate != draft.startDate || owned.endDate != draft.endDate else { continue }
            if await sync(session).succeeded { updated += 1 } else { failed += 1 }
        }
        return (updated, failed)
    }

    /// Removes the app-owned event for a session. Events not owned by the
    /// session are never touched.
    public func removeEvent(for session: WorkSession) throws {
        guard session.isLive, let identifier = session.calendarEventIdentifier else { return }
        refresh()
        guard authorization == .fullAccess else { throw CalendarSyncError.accessNotGranted(authorization) }
        if let existing = provider.event(withIdentifier: identifier), !isOwned(existing, by: session) {
            throw CalendarSyncError.eventNotOwned
        }
        if let owned = ownedEvent(for: session) {
            do {
                try provider.removeEvent(withIdentifier: owned.identifier)
            } catch let error as CalendarProviderError {
                if case .eventNotFound = error {} else { throw CalendarSyncError.removeFailed("\(error)") }
            }
        }
        clearEventReference(on: session, status: .notSynced)
        try? persistence.save()
    }

    /// Marks sessions whose app-owned event was deleted in Calendar.
    /// Returns the number of sessions updated.
    @discardableResult
    public func reconcile(_ sessions: [WorkSession]) -> Int {
        refresh()
        guard authorization == .fullAccess else { return 0 }
        var changed = 0
        for session in sessions where session.calendarSyncStatus == .synced {
            guard session.calendarEventIdentifier != nil else { continue }
            if let owned = ownedEvent(for: session) {
                // Re-link when Calendar changed the event's identifier.
                if owned.identifier != session.calendarEventIdentifier || owned.calendarIdentifier != session.eventCalendarIdentifier {
                    session.calendarEventIdentifier = owned.identifier
                    session.eventCalendarIdentifier = owned.calendarIdentifier
                    changed += 1
                }
            } else {
                clearEventReference(on: session, status: .eventMissing)
                session.calendarSyncMessage = "The Calendar event was removed outside Calendar Time Logger. Your work log is unchanged."
                changed += 1
            }
        }
        if changed > 0 { try? persistence.save() }
        return changed
    }

    public func isOwned(_ event: CalendarEventRecord, by session: WorkSession) -> Bool {
        CalendarOwnership.sessionID(from: event.url) == session.id
    }

    /// The event this session owns: by stored identifier when it still points
    /// at an owned event, otherwise by searching near the session's time for
    /// an event carrying the session's ownership URL.
    public func ownedEvent(for session: WorkSession) -> CalendarEventRecord? {
        if let identifier = session.calendarEventIdentifier,
           let existing = provider.event(withIdentifier: identifier),
           isOwned(existing, by: session) {
            return existing
        }
        guard session.calendarEventIdentifier != nil || session.calendarSyncStatus != .notSynced else { return nil }
        let end = session.endedAt ?? session.startedAt
        let window = DateInterval(start: session.startedAt.addingTimeInterval(-86_400), end: max(end, session.startedAt).addingTimeInterval(86_400))
        return provider.events(in: window, calendarIdentifiers: nil).first { isOwned($0, by: session) }
    }

    // MARK: Helpers

    private func clearEventReference(on session: WorkSession, status: CalendarSyncStatus) {
        session.calendarEventIdentifier = nil
        session.eventCalendarIdentifier = nil
        session.calendarSyncStatus = status
        session.calendarSyncMessage = nil
    }

    private func record(_ error: CalendarSyncError, on session: WorkSession) -> CalendarSyncOutcome {
        session.calendarSyncStatus = .failed
        session.calendarSyncMessage = error.storedMessage
        try? persistence.save()
        return .failed(error)
    }

    private func map(_ error: CalendarProviderError) -> CalendarSyncError {
        switch error {
        case .calendarNotFound: .calendarNotFound
        case .calendarReadOnly(let name): .calendarReadOnly(name)
        case .eventNotFound: .saveFailed("The existing event could not be found.")
        case .operationFailed(let reason): .saveFailed(reason)
        }
    }
}
