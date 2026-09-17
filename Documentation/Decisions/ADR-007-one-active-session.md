# ADR-007 — One active session at a time

Status: Accepted
Date: 2026-09-15

## Context

Users record what they're working on right now. Parallel timers complicate the menu bar (whose template styles it?), the Calendar (overlapping events), and analytics (double-counted time).

## Decision

V1 allows **exactly one open (active or paused) session**. `SessionService.start` throws `sessionAlreadyActive` if one exists. To switch work, the user finishes (or cancels) and starts another. If the wrong template was started, **Change Template** moves the open session to another template while keeping its timing.

If the store somehow contains several open sessions, the most recent is treated as active; the others surface after it ends.

## Alternatives considered

- **Multiple simultaneous sessions.** More flexible but conflicts with the menu bar model and inflates totals. Not requested for V1.
- **Auto-finish the current session when starting another.** Surprising; it could create Calendar events the user didn't intend.

## Consequences

- A clear menu bar, non-overlapping events, and honest totals.
- Users can't track overlapping activities. Revisiting this would require a new ADR.
