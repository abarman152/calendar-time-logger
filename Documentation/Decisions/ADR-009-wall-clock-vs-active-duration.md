# ADR-009 — Wall-clock vs active duration

Status: Accepted
Date: 2026-09-15

## Context

A session from 10:00 to 12:24 with a pause from 11:15 to 11:40 has 2h 24m of wall-clock time and 1h 59m of active work. Different surfaces need different numbers, and the timer must stay correct across sleep and relaunch.

## Decision

- Store only timestamps: `startedAt`, `endedAt`, and `[PauseInterval(start, end?)]`.
- `SessionTiming` computes:
  - **wall clock** = end (or now) − start, never negative
  - **paused** = the sum of pauses clipped to the session
  - **active** = wall clock − paused
  
  Results are rounded to milliseconds to prevent floating-point drift showing as a lost minute.
- **The Calendar event** spans the wall-clock interval (10:00 AM → 12:24 PM); its notes list active and paused time.
- **The live timer, Work Logs, Dashboard, analytics, and reminders** use active duration.
- Sessions are attributed to the **day they started** for grouping and totals.
- The UI refreshes once per second from a `SessionClock`, but values are always recomputed from timestamps.

## Alternatives considered

- **An incrementing counter.** Drifts and breaks across sleep and relaunch.
- **Splitting the Calendar event around pauses.** Clutters the calendar and doesn't match "the session interval".
- **Splitting sessions across midnight.** Accurate but complex; deferred.

## Consequences

- Timing is robust against suspension, sleep, scheduling delays, and crashes.
- Cross-midnight sessions count entirely toward their start day (a known limitation).
