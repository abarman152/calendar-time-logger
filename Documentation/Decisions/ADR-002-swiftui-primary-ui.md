# ADR-002 — SwiftUI as the primary UI framework

Status: Accepted
Date: 2026-09-15

## Context

The app needs a main window, a menu bar item with a popover, a Settings window, charts, and forms, and it should look native on macOS 27, including Liquid Glass controls.

## Decision

Use **SwiftUI** for all UI: `Window`, `MenuBarExtra` (`.window` style), `Settings` with `TabView`, `NavigationSplitView`, `Form(.grouped)`, `.inspector`, Swift Charts, and `.glass`/`.glassProminent` button styles. Use **AppKit only where SwiftUI has no equivalent**:

- `NSWorkspace` for sleep and wake notifications and for opening Calendar and System Settings
- `NSImage` output of `ImageRenderer` for colored menu bar labels ([ADR-008](ADR-008-menu-bar-customization.md))
- `NSApp.orderFrontCharacterPalette` for the emoji picker, and `NSApp.activate`/`terminate`

## Alternatives considered

- **AppKit with NSStatusItem.** Offers finer control over the status item but far more code, and diverges from the rest of a SwiftUI app.
- **Mixed AppKit windows with SwiftUI content.** No capability gap justified it.

## Consequences

- Less code and consistent, native styling.
- Some behaviors depend on SwiftUI scene semantics. For example, presenting a sheet at launch proved unreliable, which led to inline recovery ([ADR-012](ADR-012-recovery-and-sleep.md)).
- AppKit use is confined to the app target, so the core package stays UI-free.
