# Release Process

This describes how to ship a version of Calendar Time Logger. No build has been publicly distributed. The current version is 1.4.0 (6), packaged as `dist/Calendar-Time-Logger-v1.4.0.dmg`. The project is signed with a personal development team, which can't produce Developer ID–signed or notarized builds, so the DMG is development-signed and not notarized.

## 1. Prepare

- [ ] All work for the version is merged.
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are updated in **both** Debug and Release configurations ([VERSION.md](VERSION.md)).
- [ ] [CHANGELOG.md](CHANGELOG.md) has a `## [x.y.z] — YYYY-MM-DD` section with Added / Changed / Fixed / Known Limitations.
- [ ] Documentation audit per [DOCUMENTATION_RULES.md](../Development/DOCUMENTATION_RULES.md#release-documentation-rules) is complete.
- [ ] Any schema change has a migration stage, a tested upgrade path, and an ADR. Any value-level data conversion (like the 1.1.0 icon conversion) is tested against a store written by the previous version.

## 2. Verify

```bash
scripts/verify.sh --full
```

This must report passing tests, Debug and Release builds without warnings, a current and valid SF Symbols catalog, a clean static analysis, and resolving documentation links.

Then:

- [ ] Run the manual QA checklist in [TESTING.md](../Testing/TESTING.md#manual-qa-checklist) on a Release build, including real Calendar writes to a test calendar.
- [ ] Confirm entitlements on the archived app:

  ```bash
  codesign -d --entitlements - "Calendar Time Logger.app"
  ```

  The expected set is `com.apple.security.app-sandbox`, `com.apple.security.personal-information.calendars`, and `com.apple.security.files.user-selected.read-write` (export Save panel, since 1.1.0). `get-task-allow` must **not** be present in a distribution-signed build.
- [ ] Confirm `Info.plist` contains the correct version, `NSCalendarsFullAccessUsageDescription`, and the `calendartimelogger` URL scheme.
- [ ] Confirm demo mode isn't in the Release binary:

  ```bash
  strings "Calendar Time Logger.app/Contents/MacOS/Calendar Time Logger" | grep -c demoState
  ```

  The count must be `0`.

## 3. Package

```bash
scripts/package-dmg.sh
```

A clean Release build, bundle verification (bundle identifier, code signature, no DEBUG demo code, icon present, no debug artifacts), staging with an Applications shortcut, the branded background and volume icon, the Finder window layout, compression, `hdiutil verify`, and a SHA-256 file.

Output: `dist/Calendar-Time-Logger-v<version>.dmg`.

Then check the installer by hand:

- [ ] The DMG opens and the window shows the background, the app, and the Applications shortcut.
- [ ] Dragging the app onto Applications installs it, and the installed app launches.
- [ ] The installed app reports the expected version and shows the CTL menu bar item.

## 4. Archive and sign

`scripts/package-dmg.sh` signs the app with whatever identity the project uses and prints it, but does **not** notarize. For distribution beyond this Mac:

1. In Xcode, select the `calender_time_logger` scheme and **Product › Archive** (Release).
2. In the Organizer, choose **Distribute App**:
   - **Direct distribution:** Developer ID, then notarize with Apple.
   - **Mac App Store:** App Store Connect. This needs an App Store record, the privacy nutrition label (see [PRIVACY.md](../Product/PRIVACY.md)), and review.
3. Both paths require a paid Apple Developer Program team with the matching certificates. Update the target's team before archiving.

## 5. Publish

- [ ] Staple the notarization ticket (direct distribution).
- [ ] Tag the source: `v<version>` (for example `v1.1.0`).
- [ ] Publish release notes from the CHANGELOG section.
- [ ] Bump the build number for the next build.

## 6. After release

- [ ] Move any leftover `[Unreleased]` notes to the next version.
- [ ] Record issues found after release as Known Limitations or fixes in the next PATCH.
