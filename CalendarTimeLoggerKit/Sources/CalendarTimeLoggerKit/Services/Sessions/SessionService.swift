import Foundation
import Observation

public enum SessionError: Error, LocalizedError, Equatable {
    case storageUnavailable
    case sessionAlreadyActive(templateName: String)
    case noActiveSession
    case invalidTransition(InvalidSessionTransition)
    case invalidTimes(String)
    case invalidTaskName
    /// The work log was deleted while it was being edited or moved.
    case workLogDeleted
    case persistence(PersistenceError)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Work can’t be recorded because the database is unavailable."
        case .sessionAlreadyActive(let name):
            "You’re already working on \(name). Finish or cancel it before starting another session."
        case .noActiveSession:
            "There’s no session in progress."
        case .invalidTransition(let transition):
            transition.errorDescription
        case .invalidTimes(let reason):
            reason
        case .invalidTaskName:
            "Give the task a name before starting it."
        case .workLogDeleted:
            "This work log was deleted, so the change wasn’t saved."
        case .persistence(let error):
            error.errorDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .storageUnavailable, .persistence: PersistenceError.storeUnavailable("").recoverySuggestion
        case .workLogDeleted: "Select another work log in Work Logs."
        default: nil
        }
    }
}

/// The result of finishing a session, shown in the completion confirmation.
public struct SessionCompletion: Identifiable, Equatable, Sendable {
    public let log: WorkLog
    /// `nil` while Calendar sync is still running.
    public var calendarOutcome: CalendarSyncOutcome?
    public var calendarName: String?
    public var id: UUID { log.id }

    public init(log: WorkLog, calendarOutcome: CalendarSyncOutcome?, calendarName: String? = nil) {
        self.log = log
        self.calendarOutcome = calendarOutcome
        self.calendarName = calendarName
    }
}

/// Values a user can change on a completed session.
public struct SessionEdit: Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    public var notes: String
    public var tags: [String]
    public var taskPriority: TaskPriority
    public var category: String
    public var calendarIdentifier: String?

    public init(startedAt: Date, endedAt: Date, notes: String, tags: [String],
                taskPriority: TaskPriority = .default, category: String = WorkCategory.defaultName,
                calendarIdentifier: String?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.tags = tags
        self.taskPriority = taskPriority
        self.category = category
        self.calendarIdentifier = calendarIdentifier
    }

    public init(session: WorkSession) {
        self.init(
            startedAt: session.startedAt,
            endedAt: session.endedAt ?? session.startedAt,
            notes: session.notes,
            tags: session.tags,
            taskPriority: session.taskPriority,
            category: session.category,
            calendarIdentifier: session.calendarIdentifier
        )
    }
}

/// How the user chose to handle a session found open at launch.
public enum RecoveryChoice: Equatable, Sendable {
    case resume
    case finishNow
    case finishAtLastSeen
    case cancel
}

/// Runs the live session lifecycle. V1 allows one open session at a time (ADR-007).
@MainActor
@Observable
public final class SessionService {
    @ObservationIgnored private let persistence: PersistenceService
    @ObservationIgnored private let calendarService: CalendarService
    @ObservationIgnored private let notificationService: NotificationService
    @ObservationIgnored private let now: () -> Date

    /// The open (active or paused) session, if any.
    public private(set) var activeSession: WorkSession?
    /// An open session found at launch that the user hasn't acknowledged yet.
    public private(set) var pendingRecovery: WorkSession?
    /// The most recent completion, for the confirmation UI.
    public var lastCompletion: SessionCompletion?

    public init(
        persistence: PersistenceService,
        calendarService: CalendarService,
        notificationService: NotificationService,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.calendarService = calendarService
        self.notificationService = notificationService
        self.now = now
        reloadActiveSession()
        pendingRecovery = activeSession
    }

    public var canRecordWork: Bool { persistence.canRecordWork }

    /// Re-reads the open session from the store (used at launch and after a
    /// session ends, in case another open session exists).
    public func reloadActiveSession() {
        activeSession = (try? persistence.openSessions())?.first
    }

    // MARK: Lifecycle

    /// Starts a session from a template.
    ///
    /// - Parameter priority: the classification for this session. `nil` uses
    ///   the template's default. The value is copied onto the session, so
    ///   editing the template afterwards never changes recorded work.
    /// - Parameter category: the category for this session. `nil` uses the
    ///   template's category, and is copied onto the session the same way.
    @discardableResult
    public func start(template: WorkTemplate, priority: TaskPriority? = nil, category: String? = nil) throws -> WorkSession {
        try startSession(
            templateID: template.id,
            name: template.name,
            icon: template.symbolName,
            colorHex: template.colorHex,
            tags: template.tags,
            notes: "",
            priority: priority ?? template.taskPriority,
            category: category ?? template.category,
            calendarIdentifier: nil,
            behavior: template.notificationBehavior
        )
    }

    /// Starts a session for work the user named on the spot, with no template.
    @discardableResult
    public func startQuickTask(_ draft: QuickTaskDraft) throws -> WorkSession {
        guard draft.isValid else { throw SessionError.invalidTaskName }
        return try startSession(
            templateID: nil,
            name: draft.normalizedName,
            icon: QuickTaskDraft.symbolName,
            colorHex: QuickTaskDraft.color.hex,
            tags: draft.tags,
            notes: draft.notes,
            priority: draft.taskPriority,
            category: draft.category,
            calendarIdentifier: draft.calendarIdentifier,
            behavior: .default
        )
    }

    private func startSession(
        templateID: UUID?,
        name: String,
        icon: String,
        colorHex: String,
        tags: [String],
        notes: String,
        priority: TaskPriority,
        category: String,
        calendarIdentifier: String?,
        behavior: NotificationBehavior
    ) throws -> WorkSession {
        guard persistence.canRecordWork else { throw SessionError.storageUnavailable }
        if let activeSession {
            throw SessionError.sessionAlreadyActive(templateName: activeSession.templateName)
        }
        let state = try transition(.idle, .start)
        let startedAt = now()
        let session = WorkSession(
            templateID: templateID,
            templateName: name,
            templateIcon: icon,
            templateColorHex: colorHex,
            startedAt: startedAt,
            tags: TagParsing.normalize(tags),
            notes: notes,
            taskPriority: priority,
            category: canonicalCategory(category)
        )
        session.calendarIdentifier = calendarIdentifier
        session.state = state
        session.lastHeartbeatAt = startedAt
        persistence.context.insert(session)
        do {
            try persistence.save()
        } catch {
            persistence.context.delete(session)
            throw mapPersistence(error)
        }
        activeSession = session
        pendingRecovery = nil

        Task { await notificationService.sessionStarted(session, behavior: behavior) }
        return session
    }

    public func pause() throws {
        let session = try requireActiveSession()
        let next = try transition(session.state, .pause)
        let previousPauses = session.pauses
        session.pauses = previousPauses + [PauseInterval(start: now())]
        session.state = next
        session.modifiedAt = now()
        try commit { session.pauses = previousPauses; session.state = .active }
        notificationService.sessionPaused(session)
    }

    public func resume() throws {
        let session = try requireActiveSession()
        let next = try transition(session.state, .resume)
        let previousPauses = session.pauses
        var pauses = previousPauses
        if let last = pauses.indices.last, pauses[last].end == nil {
            pauses[last].end = max(pauses[last].start, now())
        }
        session.pauses = pauses
        session.state = next
        session.modifiedAt = now()
        session.lastHeartbeatAt = now()
        try commit { session.pauses = previousPauses; session.state = .paused }
        pendingRecovery = nil
        let behavior = persistence.template(id: session.templateID)?.notificationBehavior ?? .default
        Task { await notificationService.sessionResumed(session, behavior: behavior) }
    }

    /// Finishes the open session, saves it, then attempts Calendar sync.
    /// The session is persisted before Calendar is touched.
    @discardableResult
    public func finish(at finishTime: Date? = nil) async throws -> SessionCompletion {
        let session = try requireActiveSession()
        let next = try transition(session.state, .finish)
        let finishedAt = max(session.startedAt, finishTime ?? now())
        let previous = (state: session.state, pauses: session.pauses)

        session.pauses = SessionTiming(startedAt: session.startedAt, endedAt: finishedAt, pauses: session.pauses).normalizedPauses()
        session.endedAt = finishedAt
        session.state = next
        session.modifiedAt = now()
        try commit {
            session.endedAt = nil
            session.state = previous.state
            session.pauses = previous.pauses
        }

        activeSession = nil
        pendingRecovery = nil
        notificationService.sessionEnded(session)
        reloadActiveSession()

        var completion = SessionCompletion(log: WorkLog(session: session), calendarOutcome: nil)
        lastCompletion = completion

        let outcome = await calendarService.sync(session, requestAccessIfNeeded: true)
        // The Calendar permission prompt can stay up while the new work log is
        // deleted from Work Logs; the first completion then stands as it is.
        guard session.isLive else { return completion }
        completion = SessionCompletion(
            log: WorkLog(session: session),
            calendarOutcome: outcome,
            calendarName: calendarService.calendar(withIdentifier: session.eventCalendarIdentifier)?.title
        )
        if lastCompletion?.id == completion.id { lastCompletion = completion }

        let behavior = persistence.template(id: session.templateID)?.notificationBehavior ?? .default
        await notificationService.sessionCompleted(completion.log, behavior: behavior, todayTotal: todayTotal())
        if case .failed(let error) = outcome {
            await notificationService.calendarSyncFailed(completion.log, error: error)
        }
        return completion
    }

    /// Cancels the open session. It is kept as a cancelled record (not shown in
    /// Work Logs or analytics) and never creates a Calendar event.
    public func cancel() throws {
        let session = try requireActiveSession()
        let next = try transition(session.state, .cancel)
        let cancelledAt = max(session.startedAt, now())
        let previous = (state: session.state, pauses: session.pauses)
        session.pauses = SessionTiming(startedAt: session.startedAt, endedAt: cancelledAt, pauses: session.pauses).normalizedPauses()
        session.endedAt = cancelledAt
        session.state = next
        session.modifiedAt = now()
        try commit {
            session.endedAt = nil
            session.state = previous.state
            session.pauses = previous.pauses
        }
        activeSession = nil
        pendingRecovery = nil
        notificationService.sessionEnded(session)
        reloadActiveSession()
    }

    // MARK: Active session details

    public func updateActiveSession(
        notes: String? = nil,
        tags: [String]? = nil,
        taskPriority: TaskPriority? = nil,
        category: String? = nil,
        calendarIdentifier: String?? = nil
    ) throws {
        let session = try requireActiveSession()
        let previous = (notes: session.notes, tags: session.tags, priority: session.taskPriority,
                        category: session.category, calendar: session.calendarIdentifier)
        if let notes { session.notes = notes }
        if let tags { session.tags = TagParsing.normalize(tags) }
        if let taskPriority { session.taskPriority = taskPriority }
        if let category { session.category = canonicalCategory(category) }
        if let calendarIdentifier { session.calendarIdentifier = calendarIdentifier }
        session.modifiedAt = now()
        try commit {
            session.notes = previous.notes
            session.tags = previous.tags
            session.taskPriority = previous.priority
            session.category = previous.category
            session.calendarIdentifier = previous.calendar
        }
    }

    /// Changes the classification of the open session. The session keeps the
    /// value it ends with, and the Work Log records that final value.
    public func updateTaskPriority(_ priority: TaskPriority) throws {
        try updateActiveSession(taskPriority: priority)
    }

    /// Changes the category of the open session only. The template is not edited.
    public func updateCategory(_ category: String) throws {
        try updateActiveSession(category: category)
    }

    /// The category a session should have after moving to `template`.
    ///
    /// A category the session inherited follows the new template. One chosen for
    /// this session — anything other than the previous template's category, or
    /// General for a quick task — is kept.
    private func category(for session: WorkSession, movingTo template: WorkTemplate) -> String {
        let inherited = persistence.template(id: session.templateID)?.category ?? WorkCategory.defaultName
        return WorkCategory.matches(session.category, inherited) ? template.category : session.category
    }

    /// Moves the open session to another template (for example after starting
    /// the wrong one). Timing is unchanged; identity, default tags, and an inherited category follow
    /// the new template.
    public func changeTemplate(to template: WorkTemplate) throws {
        let session = try requireActiveSession()
        guard session.templateID != template.id else { return }
        let previous = (id: session.templateID, name: session.templateName, icon: session.templateIcon,
                        color: session.templateColorHex, tags: session.tags, category: session.category)
        let oldTemplateTags = Set(persistence.template(id: session.templateID)?.tags ?? [])
        let newCategory = category(for: session, movingTo: template)
        session.templateID = template.id
        session.templateName = template.name
        session.templateIcon = template.symbolName
        session.templateColorHex = template.colorHex
        session.category = WorkCategory.stored(newCategory)
        // Keep tags the user added; swap the previous template's defaults for the new ones.
        session.tags = TagParsing.normalize(template.tags + previous.tags.filter { !oldTemplateTags.contains($0) })
        session.modifiedAt = now()
        try commit {
            session.templateID = previous.id
            session.templateName = previous.name
            session.templateIcon = previous.icon
            session.templateColorHex = previous.color
            session.category = previous.category
            session.tags = previous.tags
        }
        if session.state == .active {
            let behavior = template.notificationBehavior
            Task { await notificationService.sessionResumed(session, behavior: behavior) }
        }
    }

    /// Appends a timestamped note line to the open session.
    public func appendNote(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let session = try requireActiveSession()
        let stamp = now().formatted(date: .omitted, time: .shortened)
        let line = "[\(stamp)] \(trimmed)"
        try updateActiveSession(notes: session.notes.isEmpty ? line : session.notes + "\n" + line)
    }

    /// Records that the app is still running with this session open.
    public func recordHeartbeat() {
        guard let session = activeSession, session.state == .active else { return }
        session.lastHeartbeatAt = now()
        try? persistence.save()
    }

    // MARK: Recovery

    public func resolveRecovery(_ choice: RecoveryChoice) async throws {
        guard let session = pendingRecovery, session.id == activeSession?.id else {
            pendingRecovery = nil
            return
        }
        switch choice {
        case .resume:
            if session.state == .paused { try resume() }
            pendingRecovery = nil
        case .finishNow:
            try await finish()
        case .finishAtLastSeen:
            try await finish(at: session.lastHeartbeatAt ?? now())
        case .cancel:
            try cancel()
        }
    }

    public func dismissRecovery() {
        pendingRecovery = nil
    }

    // MARK: System events

    /// Pauses a running session when the Mac sleeps. Returns whether it paused.
    @discardableResult
    public func pauseForSystemSleep() -> Bool {
        guard activeSession?.state == .active else { return false }
        return (try? pause()) != nil
    }

    // MARK: Completed sessions

    /// Edits a completed session and updates its app-owned Calendar event.
    @discardableResult
    public func edit(_ session: WorkSession, with edit: SessionEdit) async throws -> CalendarSyncOutcome {
        guard session.isLive else { throw SessionError.workLogDeleted }
        guard session.state == .completed else { throw SessionError.invalidTimes("Only completed sessions can be edited.") }
        guard edit.endedAt > edit.startedAt else {
            throw SessionError.invalidTimes("The finish time must be after the start time.")
        }
        guard edit.endedAt <= now().addingTimeInterval(60) else {
            throw SessionError.invalidTimes("The finish time can’t be in the future.")
        }
        let previous = SessionEdit(session: session)
        let previousPauses = session.pauses

        session.startedAt = edit.startedAt
        session.endedAt = edit.endedAt
        session.pauses = SessionTiming(startedAt: edit.startedAt, endedAt: edit.endedAt, pauses: previousPauses).normalizedPauses()
        session.notes = edit.notes
        session.tags = TagParsing.normalize(edit.tags)
        session.taskPriority = edit.taskPriority
        session.category = canonicalCategory(edit.category)
        session.calendarIdentifier = edit.calendarIdentifier
        session.modifiedAt = now()
        try commit {
            session.startedAt = previous.startedAt
            session.endedAt = previous.endedAt
            session.pauses = previousPauses
            session.notes = previous.notes
            session.tags = previous.tags
            session.taskPriority = previous.taskPriority
            session.category = previous.category
            session.calendarIdentifier = previous.calendarIdentifier
        }
        return await calendarService.sync(session)
    }

    /// Moves a completed session to another template (for example, work that
    /// was recorded under the wrong template). Timing and notes are unchanged;
    /// identity, default tags, and an inherited category follow the new template, and the app-owned
    /// Calendar event is updated.
    @discardableResult
    public func reassignTemplate(of session: WorkSession, to template: WorkTemplate) async throws -> CalendarSyncOutcome {
        guard session.isLive else { throw SessionError.workLogDeleted }
        guard template.isLive else { throw SessionError.persistence(.itemDeleted) }
        guard session.state == .completed else { throw SessionError.invalidTimes("Only completed sessions can be moved to another template.") }
        guard session.templateID != template.id else { return .skipped }
        let previous = (id: session.templateID, name: session.templateName, icon: session.templateIcon,
                        color: session.templateColorHex, tags: session.tags, category: session.category)
        let oldTemplateTags = Set(persistence.template(id: session.templateID)?.tags ?? [])
        let newCategory = category(for: session, movingTo: template)
        session.templateID = template.id
        session.templateName = template.name
        session.templateIcon = template.symbolName
        session.templateColorHex = template.colorHex
        session.category = WorkCategory.stored(newCategory)
        session.tags = TagParsing.normalize(template.tags + previous.tags.filter { !oldTemplateTags.contains($0) })
        session.modifiedAt = now()
        try commit {
            session.templateID = previous.id
            session.templateName = previous.name
            session.templateIcon = previous.icon
            session.templateColorHex = previous.color
            session.category = previous.category
            session.tags = previous.tags
        }
        // Only an existing event is updated; sessions not in Calendar stay that way.
        guard session.calendarSyncStatus == .synced || session.calendarEventIdentifier != nil else { return .skipped }
        return await calendarService.sync(session)
    }

    public func retryCalendarSync(_ session: WorkSession) async -> CalendarSyncOutcome {
        await calendarService.sync(session, requestAccessIfNeeded: true)
    }

    /// Retries every completed session whose sync failed or whose event went missing.
    @discardableResult
    public func retryAllCalendarSyncs() async -> Int {
        let sessions = (try? persistence.completedSessions()) ?? []
        var succeeded = 0
        for session in sessions where session.calendarSyncStatus.needsAttention {
            if await calendarService.sync(session).succeeded { succeeded += 1 }
        }
        return succeeded
    }

    /// Deletes a finished session. Optionally removes its app-owned event first;
    /// if that fails, nothing is deleted.
    ///
    /// A session that is already deleted is left alone, so a repeated
    /// confirmation neither fails nor reads the detached model.
    public func delete(_ session: WorkSession, removingCalendarEvent: Bool) throws {
        guard session.isLive else { return }
        guard session.state.isTerminal else {
            throw SessionError.invalidTimes("Finish or cancel the session before deleting it.")
        }
        if removingCalendarEvent {
            try calendarService.removeEvent(for: session)
        }
        persistence.context.delete(session)
        do {
            try persistence.save()
        } catch {
            persistence.context.rollback()
            throw mapPersistence(error)
        }
    }

    // MARK: Queries

    /// Completed work logs, other than `session`, whose recorded time overlaps
    /// `[start, end)`. Work logs that only touch the boundary don't count.
    public func overlappingWorkLogs(excluding session: WorkSession? = nil, start: Date, end: Date) -> [WorkSession] {
        let interval = WorkInterval(start: start, end: end)
        let excludedID = session?.id
        return ((try? persistence.completedSessions()) ?? []).filter { other in
            guard other.id != excludedID, let otherEnd = other.endedAt else { return false }
            return interval.overlaps(WorkInterval(start: other.startedAt, end: otherEnd))
        }
    }

    public func todayTotal() -> TimeInterval {
        let interval = WorkAnalytics.dayInterval(containing: now())
        let logs = ((try? persistence.completedSessions()) ?? []).map { WorkLog(session: $0) }
        return WorkAnalytics.totalActiveDuration(WorkAnalytics.logs(logs, in: interval))
    }

    // MARK: Helpers

    private func requireActiveSession() throws -> WorkSession {
        guard let activeSession else { throw SessionError.noActiveSession }
        return activeSession
    }

    private func transition(_ state: SessionState, _ event: SessionEvent) throws -> SessionState {
        do {
            return try SessionStateMachine.transition(from: state, on: event)
        } catch let error as InvalidSessionTransition {
            throw SessionError.invalidTransition(error)
        }
    }

    /// A category name as stored on a session: never blank, and spelled like an
    /// existing category that differs only by case.
    private func canonicalCategory(_ name: String) -> String {
        WorkCategory.canonical(name, among: (try? persistence.availableCategories()) ?? WorkCategory.builtIn)
    }

    /// Saves, restoring in-memory values if the save fails.
    private func commit(rollback: () -> Void) throws {
        do {
            try persistence.save()
        } catch {
            rollback()
            throw mapPersistence(error)
        }
    }

    private func mapPersistence(_ error: Error) -> SessionError {
        if let error = error as? PersistenceError { return .persistence(error) }
        return .persistence(.saveFailed(error.localizedDescription))
    }
}
