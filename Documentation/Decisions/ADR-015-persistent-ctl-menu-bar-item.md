# ADR-015 — Persistent CTL menu bar identity

Status: Accepted
Date: 2026-09-16

## Context

In 1.0 the menu bar item showed a clock symbol when idle and the template while working. The app now needs a permanent, recognizable identity, **CTL**, whenever it runs. The item should become the active template during a session, return to CTL afterwards, disappear when the app quits, and never appear twice.

## Decision

- The item stays a single SwiftUI `MenuBarExtra` scene. Its lifetime is the process's: macOS removes it when the app quits or crashes, and one scene can't produce duplicates within a process.
- `MenuBarFormatter` returns `showsIdentity = true` whenever no session is open. The app draws the identity in the style chosen in Settings › Menu Bar (`MenuBarIdentityStyle`): **CTL Badge** (default; "CTL" knocked out of a rounded square like the app logo, rendered as a template image so macOS tints it), **CTL Text**, or **Clock Symbol**.
- Visibility follows only `SettingsStore.showsMenuBarItem` (`MenuBarService.isItemInserted`), never session state.
- **One copy of the app.** `SingleInstance` runs in `CalendarTimeLoggerApp.init`, before any service opens the database or the item exists. Using `AppInstancePolicy`, a newly launched copy activates the earliest-launched running copy (ties go to the lower process ID) and exits. DEBUG demo mode is exempt because it uses an in-memory store.
- Closing the main window doesn't quit the app (`applicationShouldTerminateAfterLastWindowClosed` returns `false`), so CTL stays available. `LaunchWindowPresenter` still opens the main window at launch when "Show the main window when Calendar Time Logger opens" is on, even if window restoration remembered it closed.
- The session engine doesn't know about the menu bar: `SessionService` → app state (`AppEnvironment`) → `MenuBarService`/`MenuBarFormatter` → `MenuBarLabel`.

## Alternatives considered

- **An AppKit `NSStatusItem` controller.** More control, but it would replace the working `MenuBarExtra` popover and scene lifecycle for no user-visible gain.
- **Showing the logo PNG.** A solid square is illegible at menu bar size and wouldn't adapt to light, dark, or highlighted menu bars.
- **No single-instance guard.** Two copies would show two CTL items and write to the same SwiftData store.

## Consequences

- CTL is present from launch to quit; verified with the Accessibility API (exactly one status item, labels for idle, working, and paused, removal on quit).
- A second copy quits silently after activating the first. Demo mode can run beside the installed app.
