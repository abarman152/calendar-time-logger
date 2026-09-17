# Development

## Requirements

- macOS 27
- Xcode 27. The project was built with Xcode 27.0 beta (27A5252f) and Swift 6.4.
- An Apple Development signing identity. The project uses automatic signing with team `SUDJAF8XLZ`; change it in the target's Signing & Capabilities if you use a different team.

If `xcode-select -p` points to `/Library/Developer/CommandLineTools`, either switch it with `sudo xcode-select -s /Applications/Xcode-beta.app` or prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## Getting started

```bash
open calender_time_logger/calender_time_logger.xcodeproj
```

Select the `calender_time_logger` scheme and run it. The local package `CalendarTimeLoggerKit` resolves automatically.

Command line:

```bash
scripts/verify.sh          # package tests + Debug build
scripts/verify.sh --full   # + icon audits, static analyzer, Release build, documentation checks
```

## Repository layout

```
.
├── README.md                              public entry point
├── CLAUDE.md                              contributor / AI instructions
├── CalendarTimeLoggerKit/                 Swift package (core)
│   ├── Package.swift
│   ├── Sources/CalendarTimeLoggerKit/
│   │   ├── Domain/                        models, state machine, timing
│   │   ├── Navigation/                    AppSection (sidebar destinations)
│   │   ├── Persistence/                   SwiftData schema + PersistenceService
│   │   ├── Services/
│   │   │   ├── Analytics/  Calendar/  Export/  MenuBar/  Notifications/  Sessions/  Settings/
│   │   └── Utilities/
│   └── Tests/CalendarTimeLoggerKitTests/  Swift Testing suites + Support/ mocks
├── calender_time_logger/
│   ├── calender_time_logger.xcodeproj
│   └── calender_time_logger/              app target sources (file-system synchronized group)
│       ├── App/                           App, AppEnvironment, RootView, commands, DemoMode
│       ├── AppIntents/
│       ├── Features/                      Analytics, Calendar, Dashboard, Export, MenuBar,
│       │                                  Onboarding, Sessions, Settings, Templates, WorkLogs
│       ├── UI/Components/  UI/DesignSystem/
│       └── Resources/                     Assets.xcassets, Info.plist
├── Documentation/                         all documentation (see Documentation/README.md)
│   ├── Architecture/  Decisions/  Design/  Development/  Product/  Releases/  Testing/
│   └── User Guide/                        how to use the app, written for users
├── scripts/                               verify.sh, check-doc-links.sh, audit-doc-emoji.py,
│                                          audit-ui-icons.py, generate-symbol-catalog.py,
│                                          generate-app-icon.swift, package-dmg.sh,
│                                          dmg/render-background.swift
├── dist/                                  built DMGs (ignored by version control)
└── logo.png                               original logo (unchanged)
```

The Xcode target uses a **file-system synchronized group**: new Swift files inside `calender_time_logger/calender_time_logger/` are picked up automatically. `Resources/Info.plist` is excluded from the Copy Resources phase through a build-file exception set, because it is merged into the generated Info.plist instead.

The target and scheme keep the original internal name `calender_time_logger`. The user-facing product name is **Calendar Time Logger** (`PRODUCT_NAME`, `CFBundleDisplayName`); the Swift module is `CalendarTimeLogger`.

## Where code goes

| Code | Location | Rule |
| --- | --- | --- |
| Models, state, rules, formatting | `CalendarTimeLoggerKit/Domain`, `Utilities` | No AppKit or SwiftUI |
| Anything that talks to EventKit, UserNotifications, SwiftData | `CalendarTimeLoggerKit/Services`, `Persistence` | Behind a protocol when it touches a system service |
| SwiftUI views | App target `Features/` and `UI/` | Views call `AppEnvironment` actions, not EventKit |
| AppKit | App target only | Only where SwiftUI has no equivalent (`NSWorkspace`, `NSImage` for the menu bar, `NSSavePanel` for exports) |

New behavior in the package needs tests (see [TESTING.md](../Testing/TESTING.md)).

## Conventions

- Swift 6 language mode with strict concurrency. Services are `@MainActor`; value types are `Sendable`.
- The injectable clock (`now: () -> Date`) is used everywhere time matters; never call `Date()` in service logic that tests need to control.
- User-facing strings use the full product name, **Calendar Time Logger**.
- Errors shown to users conform to `LocalizedError` with `errorDescription` and `recoverySuggestion`.
- Don't add third-party dependencies without an ADR.
- No emoji in the UI. Icons are SF Symbols; template icons must come from `SymbolCatalog`.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/verify.sh [--full]` | Tests and builds; `--full` adds audits, the analyzer, a Release build, and documentation checks |
| `scripts/check-doc-links.sh` | Documentation layout and relative links (percent-encoded paths are decoded first) |
| `scripts/audit-doc-emoji.py` | No emoji in any Markdown file |
| `scripts/audit-ui-icons.py` | Every SF Symbol literal exists on the deployment target; no emoji in UI sources |
| `scripts/generate-symbol-catalog.py [--check]` | Regenerates or validates the template icon catalog |
| `scripts/generate-app-icon.swift` | Regenerates the app icon and brand logo images |
| `scripts/package-dmg.sh` | Clean Release build → verified `dist/Calendar-Time-Logger-v<version>.dmg` |
| `scripts/dmg/render-background.swift` | Regenerates the installer background (1x and 2x) |

## SF Symbols catalog

Template icons come from `CalendarTimeLoggerKit/Sources/CalendarTimeLoggerKit/Domain/SymbolCatalog+Generated.swift`, which is generated. To add or change symbols, edit the `CATEGORIES` list in `scripts/generate-symbol-catalog.py`, then:

```bash
/usr/bin/python3 scripts/generate-symbol-catalog.py          # regenerate
/usr/bin/python3 scripts/generate-symbol-catalog.py --check  # verify (part of verify.sh --full)
```

The script reads the SF Symbols catalog installed with macOS (`/System/Library/CoreServices/CoreGlyphs.bundle`) and fails if a name doesn't exist or needs a macOS newer than the deployment target. If a symbol is added to `TemplateSymbol.legacyEmojiMap`, it must also be in the catalog (a test enforces this).

## Demo mode (DEBUG only)

Demo mode lets you inspect every screen without touching real data or calendars. It's compiled only into Debug builds.

```bash
APP=".build/DerivedData/Build/Products/Debug/Calendar Time Logger.app"
open -n "$APP" --args -demo -demoState active -demoSection dashboard
```

| Argument | Values |
| --- | --- |
| `-demo` | Required. In-memory store, separate defaults suite, Calendar sync and notifications off, sample calendars, 30 days of sample data |
| `-demoState` | `idle`, `active` (default), `paused`, `recovery`, `completion`, `export` (opens the export sheet), `onboarding`, `quickTask` (opens Quick New Task), `startSession` (opens Start Work), `priority` (a running session with the Change Category and Priority sheet), `categories` (opens Manage Categories) and `newTemplate` (opens the New Template sheet), both with `-demoSection templates` |
| `-demoSection` | `dashboard`, `templates`, `workLogs`, `calendar`, `analytics`, `settings`, `about` |
| `-demoMenuWindow` | Also opens the menu bar popover content in a normal window |
| `-demoExportMenuBarLabels` | Writes rendered menu bar labels (every mode; automatic, colored, and background; active and paused; light and dark) and the CTL outline and mark images to the app's temporary directory |
| `-demoLegacyIcons` | Stores 1.0-style emoji icons in the demo data, then runs the icon migration |
| `-demoSyncFailure` | Records one of today's sessions as a failed Calendar sync, to show the Sync Failed states and the Dashboard banner. Without it the demo has no Calendar warnings. |
| `-demoAnalyticsRange` | `today`, `thisWeek` (default), `last7`, `thisMonth`, `last30`: the range Analytics opens with |
| `-demoExpandCategories` | Opens Analytics with the per-category breakdown expanded |
| `-demoSettingsPane` | `general` (default), `menuBar`, `notifications`, `appearance`, `export`, `calendar`, `privacy`: the pane Settings opens with (use with `-demoSection settings`) |
| `-demoExportDirectory <path>` | Exports all work logs to that folder without the Save panel (the path must be writable inside the sandbox) |
| `-demoExportColumns <preset>` | `basic`, `detailed`, `priorityAnalysis`, `categoryAnalysis`, or `everything` for that export; the default columns otherwise |
| `-demoAppearance` | `system`, `light`, `dark` |
| `-demoWindowSize` | Main window size for screenshots, for example `1440x900` |
| `-demoPersistentStore` | Keeps the demo data on disk (`CalendarTimeLogger-Demo.store` in the app's sandbox temporary directory) and its settings in their own defaults suite, so quitting and relaunching shows whether edits, deletes, and settings persist. Sample data is written only when that store is new. Calendar sync and notifications are still off. Use with `-demoState idle`: other states add a session on every launch. Never the real store. |
| `-demoResetStore` | With `-demoPersistentStore`, deletes that store and its settings first |

The demo seed covers 30 consecutive days (lighter at weekends), gives the five templates their default categories and a spread of task priorities, records one quick task and one cancelled session, so every screen, date range, category, and priority combination has data.

Demo mode seeds today's sessions shortly before the launch time, so the Dashboard has data at any hour. It isn't subject to the single-instance rule, so it can run beside an installed copy (each shows its own CTL item).

Demo mode uses `DemoCalendarProvider`, an in-memory stand-in with four sample calendars (Work, Study, Projects, Holidays). It never reads the real calendar list, so no personal calendar name can appear in a screenshot, and it never writes to Calendar.

## App icon and brand images

The app icon, the `BrandLogo` images (About, menu bar popover footer), and the `CTLWordmark` image (menu bar CTL mark, welcome screen) are generated from the original `logo.png`: the script lifts its white "CTL" glyphs as a mask and draws them, only ever scaled down, onto a black body:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift scripts/generate-app-icon.swift
```

- Output: `Resources/AppIcon.icns` (the app icon, full bleed), `Resources/Assets.xcassets/AppIcon.appiconset/icon_{16,32,64,128,256,512,1024}.png` and `BrandLogo.imageset/logo_{512,1024}.png` (rounded), `CTLWordmark.imageset/ctl_wordmark.png` (the wordmark, white on clear), and `Documentation/Design/Assets/AppIcon-1024.png`.
- The app icon is the `.icns`, declared by `CFBundleIconFile`. An asset-catalog app icon is composited onto a gray compatibility plate on macOS 26 and later, so `ASSETCATALOG_COMPILER_APPICON_NAME` is deliberately not set. See [Design/BRANDING.md](../Design/BRANDING.md) and [ADR-024](../Decisions/ADR-024-flat-icns-app-icon.md).
- The icon cache only picks up a change after the bundle is replaced, `touch`ed, and the Dock restarted.
- Generated assets are committed, so a normal build never runs the generator.
- Views showing `BrandLogo` must **not** clip it to a rounded rectangle: the image already includes the icon margin.
- `logo.png` at the repository root is the original brand artwork. It stays unchanged and is the generator's input, so it must remain in the repository. The DMG background (`scripts/dmg/render-background.swift`) reads the generated `CTLWordmark` image.

## Release packaging

```bash
scripts/package-dmg.sh          # → dist/Calendar-Time-Logger-v<version>.dmg
```

A clean Release build, bundle verification (identifier, signature, no demo code, no debug artifacts), the branded installer window laid out with Finder, then `hdiutil verify` and a checksum. macOS asks once for permission to control Finder. See [RELEASE.md](../Releases/RELEASE.md) and [ADR-020](../Decisions/ADR-020-dmg-packaging.md).

## Data locations (sandboxed)

- Store: `~/Library/Containers/abirbarman.calender-time-logger/Data/Library/Application Support/Calendar Time Logger/CalendarTimeLogger.store`
- Preferences: the app's container `UserDefaults` (including the `migration.sfSymbolIcons.v1` flag)

To reset local data during development, quit the app and delete the app's container.
