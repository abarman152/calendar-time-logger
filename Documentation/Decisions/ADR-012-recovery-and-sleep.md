# ADR-012 — Session recovery and sleep behavior

Status: Accepted
Date: 2026-09-15

## Context

An open session must never be silently discarded when the app quits, crashes, or the Mac sleeps. The timer is timestamp-based, so an open session keeps accumulating time while the app isn't running, which may or may not reflect real work.

## Decision

- **On launch**, an open session is loaded as active and flagged `pendingRecovery`. The Dashboard and the menu bar popover show **Active Session Detected** with **Resume Session**, **Finish Work**, and **Cancel Session**.
- A **heartbeat** (`lastHeartbeatAt`) is saved every 60 seconds and before sleep. When it's more than 5 minutes old, the Dashboard's recovery card also offers **Finish at <time>**, which finishes the session at the last moment the app was known to be running.
- Recovery UI is **inline, not a launch-time sheet**. During development, presenting a sheet at launch prevented the main window from appearing, so the inline card avoids that failure mode and doesn't block the app.
- **Sleep:** the timer keeps running by default (the user may be working away from the Mac). The setting **Pause the session when my Mac sleeps** pauses at `willSleep`; the session is not auto-resumed, and a notice explains why it's paused.

## Alternatives considered

- **Auto-finish at the last heartbeat.** Could cut off real work done away from the Mac.
- **Always pause on sleep.** Wrong for meetings or reading away from the computer; available as an option instead.
- **A modal sheet at launch.** Unreliable during development, as described above, and blocks unrelated tasks.

## Consequences

- No session is lost. Users decide how to interpret time spent while the app wasn't running.
- A heartbeat save every minute while working is a small, periodic write.
