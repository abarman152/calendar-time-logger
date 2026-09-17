# ADR-008 — Menu bar customization model

Status: Superseded by ADR-016 (emoji badge and rendering details); the configuration model still applies
Date: 2026-09-15

## Context

Each template controls how it appears in the menu bar: five display modes, a separator, visibility, and icon, name, and duration colors. `MenuBarExtra` labels are normally rendered as template (monochrome) content, so colors set on `Text` are ignored. Emoji can't be tinted. The menu bar background must not be modified.

## Decision

- The per-template `MenuBarConfiguration` is stored with the template. `nil` colors mean **Auto** (match the menu bar).
- `MenuBarFormatter` (pure, in the core package) converts the running session and template configuration into styled segments, a generic SF Symbol when idle or hidden, and an accessibility label.
- **All Auto:** the label is plain `Text`, which macOS renders natively in light and dark menu bars.
- **Any custom color:** the segments are rendered with `ImageRenderer` into a **non-template `NSImage`** using the label's color scheme, so the colors survive.
- **Icon color** is shown as a tinted rounded badge behind the emoji, because emoji ignore foreground color.
- A **paused** session prepends a pause glyph in every mode, so state isn't conveyed by color alone.
- Hidden templates (`isVisible = false`) show `timer` (or `pause.circle` when paused). Idle shows `clock`.
- The configuration is read live from the template, so edits apply to a running session immediately.

## Alternatives considered

- **NSStatusItem with attributed titles.** Supports colors natively but requires replacing `MenuBarExtra` and its popover with AppKit.
- **Ignore custom colors.** Fails the requirement.
- **Tint the emoji with a colored glyph copy.** Unreliable and hurts legibility.

## Consequences

- Native appearance by default. Custom colors work in all modes (verified by rendering every mode in light and dark).
- A rendered image is recreated whenever the label refreshes (every second while a session is active). While paused, an appearance change is picked up only at the next state change or template edit.
- Contrast of custom colors is the user's choice; Auto remains the accessible default.
