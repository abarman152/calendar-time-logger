# ADR-016 — Menu bar background pill and symbol segments

Status: Accepted
Date: 2026-09-16

## Context

[ADR-008](ADR-008-menu-bar-customization.md) rendered colored menu bar items into an image and tinted a badge behind emoji, and it stated the menu bar background is never modified. Templates now use SF Symbols, need a sixth display mode (Icon + Name + Duration), and need a configurable background color for the item, as in the design reference.

## Decision

- `MenuBarConfiguration` gains `backgroundColor` and the `iconNameAndDuration` mode. It is still stored as tolerant JSON with the template, now with `"version": 2`. Version-less 1.0 data that used Name + Duration with "Show icon with name" decodes as Icon + Name + Duration, so existing templates look the same. "Show icon with name" now applies only to Name Only.
- Segments carry a `kind`. Icon and paused segments are SF Symbol names (the paused glyph is `pause.fill`), rendered as `Image(systemName:)`.
- The **background is a rounded pill drawn inside the item's own image**, not a change to the system menu bar. With a background, automatic foreground colors become white when it meets WCAG 3:1 against the fill, otherwise the more legible of white or black (`HexColor.contrastingForeground`).
- Rendering: automatic colors without a pill → template image (symbols) or plain text, so macOS tints them natively. Any custom color or pill → non-template image in the menu bar's color scheme.

## Alternatives considered

- **Modifying the menu bar or status item window background.** Not supported by public API and outside the app's own content.
- **Pure max-contrast foregrounds.** Picks black on system blue, which doesn't match macOS tinted controls.

## Consequences

- Supersedes ADR-008's emoji badge. ADR-008's other decisions (per-template configuration, pure formatter, live configuration) still apply.
- Contrast of explicitly chosen colors remains the user's choice; automatic colors stay legible.
