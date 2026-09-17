import Foundation

/// The lifecycle state of a work session.
///
/// `idle` describes the engine when no session exists; persisted sessions are
/// always `active`, `paused`, `completed`, or `cancelled`.
public enum SessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case active
    case paused
    case completed
    case cancelled

    /// A session that is still being recorded (running or paused).
    public var isOpen: Bool { self == .active || self == .paused }

    /// A session that can no longer change state.
    public var isTerminal: Bool { self == .completed || self == .cancelled }

    public var displayName: String {
        switch self {
        case .idle: "Idle"
        case .active: "Working"
        case .paused: "Paused"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

/// Events that drive the session state machine.
public enum SessionEvent: String, Sendable, CaseIterable {
    case start
    case pause
    case resume
    case finish
    case cancel
}

/// Thrown when an event is not valid for the current state.
public struct InvalidSessionTransition: Error, Equatable, LocalizedError {
    public let state: SessionState
    public let event: SessionEvent

    public var errorDescription: String? {
        "Can’t \(event.rawValue) a session that is \(state.displayName.lowercased())."
    }
}

/// The single definition of valid session transitions.
///
/// ```
/// idle ──start──▶ active ──pause──▶ paused
///                   ▲  ◀──resume──   │
///                   │                │
///             finish/cancel     finish/cancel
///                   ▼                ▼
///           completed / cancelled (terminal)
/// ```
public enum SessionStateMachine {
    public static func nextState(from state: SessionState, on event: SessionEvent) -> SessionState? {
        switch (state, event) {
        case (.idle, .start): .active
        case (.active, .pause): .paused
        case (.paused, .resume): .active
        case (.active, .finish), (.paused, .finish): .completed
        case (.active, .cancel), (.paused, .cancel): .cancelled
        default: nil
        }
    }

    public static func canApply(_ event: SessionEvent, to state: SessionState) -> Bool {
        nextState(from: state, on: event) != nil
    }

    public static func transition(from state: SessionState, on event: SessionEvent) throws -> SessionState {
        guard let next = nextState(from: state, on: event) else {
            throw InvalidSessionTransition(state: state, event: event)
        }
        return next
    }
}
