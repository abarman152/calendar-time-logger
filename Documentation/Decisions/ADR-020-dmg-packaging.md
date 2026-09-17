# ADR-020 — DMG packaging

Status: Accepted
Date: 2026-09-16

## Context

Calendar Time Logger had no installer: releases existed only as a built `.app`. A macOS app is normally delivered as a DMG with the app and an Applications shortcut, and the project needs a repeatable way to produce one.

## Decision

- **`scripts/package-dmg.sh`**, using only tools that ship with macOS (`xcodebuild`, `hdiutil`, `iconutil`, `tiffutil`, `osascript`, `shasum`). No packaging dependency is added.
- The script: clean Release build → verify the bundle → stage → create a read/write image → lay out the Finder window → compress (UDZO) → `hdiutil verify` → SHA-256. Output is `dist/Calendar-Time-Logger-v<version>.dmg`; the version comes from the built `Info.plist`, so there is one source of truth. Staging happens in a temporary directory that is always cleaned up, and `dist/` is not in version control.
- **Bundle verification is part of packaging**, not a manual step: bundle identifier, code signature, no DEBUG demo code in the binary, an icon present, and no debug artifacts inside the bundle. Any failure stops the build.
- The window layout (background, icon positions, icon size, no toolbar) is applied with Finder via AppleScript, which writes the `.DS_Store` the mounted image needs. The script fails if that file wasn't produced, so a silent layout failure can't ship.
- The **background is generated** by `scripts/dmg/render-background.swift` at 1x and 2x and shipped as a TIFF. It uses a dark branded header and a light tray for the icons, because Finder draws file labels in dark text over custom backgrounds regardless of appearance.
- Signing stays with the Xcode project's identity. The script reports who signed the app and warns when the build is development-signed; it does **not** notarize.

## Alternatives considered

- **`create-dmg` or `dmgbuild`.** Mature, but they add a Homebrew or Python dependency for a task the system tools already do.
- **Writing `.DS_Store` directly** to avoid automating Finder. It would remove the Automation permission prompt, but means reproducing an undocumented binary format.
- **A ZIP archive.** Simpler, but it doesn't communicate "drag to Applications" and loses the branded presentation.

## Consequences

- One command produces a verified, checksummed installer.
- The machine running the script needs permission to control Finder (macOS asks once), and no volume named "Calendar Time Logger" may already be mounted.
- Distribution beyond the developer's own Mac still requires Developer ID signing and notarization ([RELEASE.md](../Releases/RELEASE.md)).
