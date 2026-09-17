# ADR-019 — App icon and CTL mark generated from vector sources

Status: Partly superseded by [ADR-024](ADR-024-flat-icns-app-icon.md)
Date: 2026-09-16

## Context

The app icon was a 1024 px PNG of the original logo: a full-bleed black square with a white "CTL" wordmark, resized to each required size with `sips`. On macOS 26 and later, icons that don't follow Apple's icon grid are composited onto a **gray compatibility plate**, so in Finder, the Dock, and Spotlight the artwork appeared small, inset, and surrounded by empty margin. Resizing a bitmap also softened the small sizes, and the menu bar needed a mark that stays legible at 16–20 pt.

## Decision

- The icon is **generated from vector drawing code**, `scripts/generate-app-icon.swift`, not scaled from a bitmap. This still holds.
- Each size is rendered separately, and at 16 px and 32 px the wordmark is heavier and larger so "CTL" stays readable. This still holds.
- ~~It follows the macOS grid — a 1024 px canvas, an 824 px continuous-corner body with 100 px margins, and a soft shadow inside the margin — and IconServices then draws it without the compatibility plate.~~ **Wrong on macOS 27:** an asset-catalog app icon is plated whatever its shape. Superseded by [ADR-024](ADR-024-flat-icns-app-icon.md), which ships the icon as a full-bleed `.icns`.
- ~~The artwork keeps white "CTL" on graphite, with a purple-to-blue accent bar standing for a recorded span of time.~~ Superseded by ADR-024: the mark is flat black with the white wordmark and nothing else. `logo.png` (the original artwork) is unchanged, and the same generator still writes the `BrandLogo` images used by About, onboarding, and the popover footer.
- The **menu bar mark** is separate artwork: "CTL" in an outlined rounded square with a small chevron, drawn with `ImageRenderer` as a **template image** so macOS tints it for light, dark, and highlighted menu bars. It replaces the filled knockout badge described in [ADR-015](ADR-015-persistent-ctl-menu-bar-item.md); that ADR's lifecycle decisions still apply.
- Generated assets are committed, so building doesn't require running the generator.

## Alternatives considered

- **An Icon Composer `.icon` document** (the macOS 26 format, which also gives Liquid Glass layering). `ictool` ships with Xcode, but no schema documentation or sample document was available to author one by hand with confidence. An asset catalog that follows the grid already avoids the plate; this can be revisited with Icon Composer itself.
- **Scaling the existing PNG to fill more of the canvas.** It would still be a square that macOS plates, and small sizes would stay soft.
- **Using an SF Symbol for the app icon.** It would lose the brand and look generic among other apps.

## Consequences

- The icon fills the standard icon area in Finder, the Dock, Spotlight, About, and the DMG, verified through `NSWorkspace.icon(forFile:)`.
- Changing the artwork means editing the generator and regenerating, not editing PNGs.
- Views that show `BrandLogo` must not clip it: the image already contains the icon margin.
