# ADR-004 — WorkSession as the source of truth; Work Logs as a projection

Status: Accepted
Date: 2026-09-15

## Context

The product principle is that the user's actual work is authoritative. Work Logs, analytics, notifications, and Calendar events all describe the same session and must never disagree.

## Decision

- `WorkSession` is the **only** stored record of work. It holds timestamps, pauses, notes, tags, state, and Calendar references.
- **`WorkLog` is a value projection** built from a session on demand. It is not persisted.
- Durations are computed from timestamps, not stored.
- A session references its template by `templateID` and keeps a snapshot of the template's name, icon, and color, rather than a relationship. Deleting or renaming a template never changes recorded work.
- **Cancelled** sessions are kept with state `cancelled` and excluded from Work Logs, analytics, and Calendar.

## Alternatives considered

- **A separate persisted WorkLog entity.** Duplicates data that could drift from the session.
- **A SwiftData relationship from session to template with a nullify rule.** Loses the template's identity in old logs after deletion.
- **Deleting cancelled sessions.** Simpler, but destructive. Keeping them follows the "never lose recorded data" principle.

## Consequences

- One place to edit. Every view recomputes from the same data.
- Snapshots mean renaming a template doesn't rename past logs. Analytics show the most recent snapshot per template.
- Cancelled records accumulate and can't be viewed or discarded in V1 (a known limitation).
