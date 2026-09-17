# ADR-006 — EventKit abstraction and event ownership

Status: Accepted
Date: 2026-09-15

## Context

EventKit needs real permissions and a real calendar database, which makes it untestable directly. The app must also modify only events it created, even if identifiers are reused, events are moved, or Calendar assigns new identifiers after server sync.

## Decision

- All EventKit access goes through the `CalendarProviding` protocol. `EventKitCalendarProvider` implements it; tests use `MockCalendarProvider`.
- **Ownership marker:** each app-created event's `url` is `calendartimelogger://session/<session UUID>`. An event is owned by a session only if its URL decodes to that session's ID.
- Stored external references on the session: `calendarEventIdentifier`, `eventCalendarIdentifier`, and (via the URL) the session ID. These are never used as primary keys.
- **Locating an owned event:** first by stored identifier (verifying ownership), then by searching events within ±1 day of the session for the ownership URL. Reconciliation re-links drifted identifiers and marks deleted events `eventMissing`.
- **Never modify or delete unowned events.** If a stored identifier points to an event without the matching URL, sync creates a new owned event and removal is refused.
- The internal session ID is **not** written into event notes; notes stay human-readable.
- The app registers the `calendartimelogger` URL scheme, so clicking the event URL opens the session.

## Alternatives considered

- **A marker in the event notes.** Users can edit notes and it clutters them; the product brief asked to avoid exposing internals.
- **Trusting `eventIdentifier` alone.** Identifiers can change when events move or sync; that would cause duplicates or false "missing" states.
- **`calendarItemExternalIdentifier`.** Not guaranteed unique or stable across all account types.
- **A dedicated "Calendar Time Logger" calendar.** Removes user choice of calendars, which is a core requirement.

## Consequences

- Calendar logic is fully unit tested, including ownership and identifier drift.
- The event URL is visible in Calendar; it doubles as a deep link.
- If a user removes the URL from an event, the app treats the event as unowned and won't update or delete it; a later sync creates a new event.
