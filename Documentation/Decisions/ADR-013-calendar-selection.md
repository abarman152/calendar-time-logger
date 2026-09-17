# ADR-013 — Calendar selection and missing calendars

Status: Accepted
Date: 2026-09-15

## Context

Users have several calendars (Work, Personal, University, and so on). They need a global default, per-template choices, and occasionally a different calendar for a single session. Calendars can be deleted or be read-only.

## Decision

- **Resolution order:** session override → template calendar → global default (Settings) → system default calendar.
- **Per-session override** is available in Work Log details (and for the open session through `SessionService.updateActiveSession`). It changes that one event and doesn't affect the template.
- Pickers list only **writable** calendars, grouped by account. A stored identifier that no longer exists shows as "Unavailable Calendar".
- If the resolved calendar **no longer exists** or is **read-only**, sync **fails** with an actionable message. It does not fall back to the next level.

## Alternatives considered

- **Silently fall back to the next calendar.** Events would land in unexpected calendars without the user noticing.
- **No per-session override.** Simpler, but corrections (for example, a session that belonged to a different project) would require editing the event in Calendar, which the app would then overwrite.

## Consequences

- Predictable event placement; problems are visible in Sync Issues.
- Changing a template's calendar doesn't move existing events (a known limitation).
