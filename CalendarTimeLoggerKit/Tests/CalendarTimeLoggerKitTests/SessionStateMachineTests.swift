import Testing
@testable import CalendarTimeLoggerKit

@Suite("Session state machine")
struct SessionStateMachineTests {
    @Test("Valid lifecycle idle → active → paused → active → completed")
    func validLifecycle() throws {
        var state = SessionState.idle
        state = try SessionStateMachine.transition(from: state, on: .start)
        #expect(state == .active)
        state = try SessionStateMachine.transition(from: state, on: .pause)
        #expect(state == .paused)
        state = try SessionStateMachine.transition(from: state, on: .resume)
        #expect(state == .active)
        state = try SessionStateMachine.transition(from: state, on: .finish)
        #expect(state == .completed)
    }

    @Test("Finishing or cancelling while paused is allowed")
    func finishAndCancelFromPaused() {
        #expect(SessionStateMachine.nextState(from: .paused, on: .finish) == .completed)
        #expect(SessionStateMachine.nextState(from: .paused, on: .cancel) == .cancelled)
        #expect(SessionStateMachine.nextState(from: .active, on: .cancel) == .cancelled)
    }

    @Test("Terminal states reject every event", arguments: [SessionState.completed, .cancelled], SessionEvent.allCases)
    func terminalStatesRejectEvents(state: SessionState, event: SessionEvent) {
        #expect(SessionStateMachine.nextState(from: state, on: event) == nil)
        #expect(throws: InvalidSessionTransition(state: state, event: event)) {
            try SessionStateMachine.transition(from: state, on: event)
        }
    }

    @Test("Invalid transitions are rejected")
    func invalidTransitions() {
        #expect(!SessionStateMachine.canApply(.pause, to: .paused))
        #expect(!SessionStateMachine.canApply(.resume, to: .active))
        #expect(!SessionStateMachine.canApply(.start, to: .active))
        #expect(!SessionStateMachine.canApply(.pause, to: .idle))
        #expect(!SessionStateMachine.canApply(.finish, to: .idle))
    }

    @Test("Exactly the documented transitions exist")
    func transitionTableIsComplete() {
        var valid: [String] = []
        for state in SessionState.allCases {
            for event in SessionEvent.allCases where SessionStateMachine.canApply(event, to: state) {
                valid.append("\(state.rawValue).\(event.rawValue)")
            }
        }
        #expect(Set(valid) == [
            "idle.start", "active.pause", "active.finish", "active.cancel",
            "paused.resume", "paused.finish", "paused.cancel"
        ])
    }
}
