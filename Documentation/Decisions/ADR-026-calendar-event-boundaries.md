# ADR-026 — Calendar Event Boundary Semantics

Status: Accepted
Date: 2026-09-17

## Context

Two sessions recorded back to back — 10:00 to 11:00, then 11:00 to 12:00 — could look untidy in Apple Calendar: the two events appeared to share the 11:00 minute and were drawn side by side, as if they overlapped.

The investigation followed the whole path from a session to an `EKEvent`:

- `SessionService.start`, `finish`, `cancel`, and recovery take each timestamp from the injected clock once. Nothing rounds, pads, or adds or subtracts a minute. Finishing clips pauses to `[startedAt, endedAt]`.
- `CalendarService.makeDraft` passed `session.startedAt` and `session.endedAt` straight through, and `EventKitCalendarProvider.saveEvent` wrote them to `startDate` and `endDate` unchanged. Updates rewrite the same two values on the same owned event.
- Calendar Time Logger has no custom calendar timeline: its Calendar screen lists access, calendars, and sync issues, so there is no in-app rendering to fix.

That left two real causes, both about **seconds**:

1. **Hidden seconds in Edit Entry.** The work log edit sheet used `DatePicker` with hours and minutes only. A macOS date picker keeps the seconds of the value it edits, so changing a start of 11:02:15 to "11:00" stored 11:00:15. Editing a session to begin where another ended at 11:00:48 therefore created a real overlap of up to a minute that the UI didn't show. Both events then read "11:00" in Calendar, and Calendar laid them out side by side because they genuinely overlap.
2. **Sub-minute recorded times.** Live sessions end and start at whatever second you click, for example 11:00:40 and 11:00:52. They don't overlap, but both events occupy part of the 11:00 minute, which Calendar's minute grid can't show cleanly.

The actual EventKit values for the owner's existing events couldn't be inspected from the development shell (macOS privacy protection blocks reading the Calendar database), so the values written were verified through the provider boundary in tests instead.

## Decision

- **Intervals are half-open, `[start, end)`.** `WorkInterval` compares recorded times as they are. Two intervals overlap only when `a.start < b.end && b.start < a.end`; `a.end == b.start` is *adjacent*, not overlapping. `WorkInterval.relation(to:)` reports overlapping (with the shared seconds), adjacent, or separated (with the gap).
- **Recorded timestamps are never changed for presentation.** Work Logs, Analytics, and exports always use the exact recorded times.
- **Calendar event timing is a setting** (`CalendarEventTiming`, Settings › Calendar › Event Times, persisted as `calendar.eventTiming`):
  - **Keep exact times** (default): the event's `startDate` and `endDate` are the session's recorded start and finish, to the second.
  - **Round to the nearest minute**: only the *event's* start and finish are each rounded to the nearest minute. Rounding both ends with the same monotonic rule cannot reverse order, so sessions that don't overlap in Work Logs never overlap in Calendar, and sessions a few seconds apart meet on one minute. A session shorter than half a minute keeps its exact times rather than gaining invented length.
- **Edit Entry clears hidden seconds only when you change a time.** `MinuteEditing.pickedTime` keeps the recorded value when the picked minute is unchanged and stores the whole minute when it changed, so choosing 11:00 stores 11:00:00.
- **Overlaps are shown, not blocked.** Edit Entry lists completed work logs whose time overlaps the edited times (`SessionService.overlappingWorkLogs`), using the half-open rule, and still allows saving: overlapping work can be legitimate, and the product never refuses to record what the user says happened.
- **Existing events are not rewritten automatically.** Changing the setting applies to events created or updated afterwards. **Update Existing Events…** (with confirmation) calls `CalendarService.applyEventTimingToExistingEvents`, which touches only completed, synced sessions whose app-owned event still exists (found by the ownership URL, [ADR-006](ADR-006-eventkit-abstraction-and-ownership.md)) and whose event times differ. It never recreates missing events, never creates duplicates, never changes a work log, and changes nothing the second time it runs.

## Why the default is "Keep exact times"

The session is the source of truth and Calendar is its derived representation ([ADR-004](ADR-004-worksession-source-of-truth.md), [ADR-005](ADR-005-calendar-as-derived-representation.md)). An event that matches the work log to the second can always be reconciled with it; a rounded one cannot be compared exactly. Rounding is useful and safe, but it is a presentation choice the user should make.

## Alternatives considered

- **Start the next session at 11:01, or end the previous one at 10:59.** Changes recorded work to make a picture tidier, and the rule is exactly what the product forbids.
- **Always round events to the minute.** Fixes the picture for everyone, but silently makes the event disagree with the work log and breaks the "real start and finish times" promise for users who read event details.
- **Snap a new session's start to the previous session's end when they are seconds apart.** Rewrites recorded time and needs an arbitrary threshold.
- **Block saving an overlapping edit.** Overlaps can be intentional (a correction recorded before the other log is fixed), and blocking would push users to delete data instead.

## Consequences

- Adjacent sessions are treated consistently everywhere the app compares times, and tests pin the boundary cases: 10:00–11:00 / 11:00–12:00 adjacent; 10:59 overlap by a minute; 11:00:15 exact-second adjacency; an 11:00:01 one-second gap; 11:01 a one-minute overlap.
- With exact times, Calendar can still show two sessions a few seconds apart sharing a minute row. The setting explains this and offers rounding.
- A work log edited through the picker loses its sub-minute part on the time that was changed, which is what the user chose on a minute-precision control.
- Covered by `CalendarBoundaryTests`.
