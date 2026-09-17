# ADR-005 — Apple Calendar as a derived representation

Status: Accepted
Date: 2026-09-15

## Context

Calendar events are the output of finished work. EventKit can fail for many reasons: no permission, restricted access, a deleted calendar, a read-only calendar, or a save error. Users must never lose a work record because of that.

## Decision

- **No event is created when a session starts.** Sync happens only after Finish Work, and only after the completed session has been saved.
- Every sync outcome is stored on the session (`calendarSyncStatus`: `notSynced`, `synced`, `failed`, `eventMissing`, plus a human-readable message). Failures are retryable.
- The event spans the session's **wall-clock interval** ([ADR-009](ADR-009-wall-clock-vs-active-duration.md)).
- Edits to a finished session re-sync (update) its event. Deleting a log can optionally remove its event; if removal fails, nothing is deleted.
- **Permission:** full access is required. It's requested only when the user connects Calendar, or at the first Finish Work if access was never requested, so the request has clear context. Denied or write-only access is never re-prompted; the UI points to System Settings.

## Alternatives considered

- **Create the event at start and extend it live.** Violates the product rule that planned or partial events never appear, and leaves stale events after crashes.
- **Write-only access.** Can't list calendars for selection or update or reconcile the app's own events.
- **Request access at launch.** An unnecessary, context-free prompt.

## Consequences

- Recorded work is always safe; Calendar can lag and catch up.
- Users with Calendar access denied still get a fully working time logger.
- The first Finish Work may show the system permission prompt while the completion confirmation reads "Adding to Calendar…".
