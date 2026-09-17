# Architecture

This document describes how Calendar Time Logger 1.1.0 is built. It covers only what the code does today. Decisions and their trade-offs live in [Documentation/Decisions](../Decisions/).

## Guiding rule

**`WorkSession` is the source of truth. Apple Calendar is a derived representation.**

```
User action ──▶ SessionService ──▶ SwiftData (saved first)
                                        │
                                        ▼
                                  CalendarService ──▶ CalendarProviding ──▶ EventKit
                                        │
                                        ▼
                         sync status stored back on the session
```

Calendar is only touched after the session has been saved. Every Calendar outcome, success or failure, is recorded on the session itself.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ App target: "Calendar Time Logger" (SwiftUI, AppKit edges)   │
│  App/          composition root, scenes, commands, demo mode  │
│  Features/     Dashboard, Templates, Sessions, WorkLogs,      │
│                Calendar, Analytics, Settings, MenuBar,        │
│                Export, Onboarding                             │
│  UI/           DesignSystem (theme, cards), Components        │
│                (template icon, symbol picker, pickers)        │
│  AppIntents/   Start / Pause-Resume / Finish Work             │
└──────────────────────────────┬───────────────────────────────┘
                               │ imports
┌──────────────────────────────▼───────────────────────────────┐
│ CalendarTimeLoggerKit (Swift package; no AppKit/SwiftUI)      │
│  Domain/       SessionState + SessionStateMachine,            │
│                SessionTiming, WorkTemplate, WorkSession,      │
│                WorkLog, TaskPriority, QuickTaskDraft,         │
│                MenuBarConfiguration,                          │
│                NotificationBehavior, CalendarConfiguration,   │
│                HexColor, SymbolCatalog, TemplateSymbol        │
│  Persistence/  Versioned SwiftData schema, PersistenceService │
│  Navigation/   AppSection (sidebar destinations)              │
│  Services/     Sessions, Calendar, Notifications, MenuBar,    │
│                Analytics, Settings, Export (XLSX)             │
│  Utilities/    DurationFormatting, TagParsing, JSON coding    │
└──────────────────────────────────────────────────────────────┘
```

The package is the domain and service layer. It imports Foundation, SwiftData, Observation, EventKit, and UserNotifications, all of which are also available on iOS and watchOS. The app target owns everything AppKit- or SwiftUI-specific ([ADR-011](../Decisions/ADR-011-core-swift-package.md)).

## Domain

| Type | Kind | Purpose |
| --- | --- | --- |
| `SessionState` | enum | `idle`, `active`, `paused`, `completed`, `cancelled` |
| `SessionStateMachine` | enum | The only definition of valid transitions (`start`, `pause`, `resume`, `finish`, `cancel`) |
| `SessionTiming` | struct | Wall-clock, paused, and active durations computed from timestamps; pause normalization |
| `WorkTemplate` | `@Model` | How a kind of work is recorded: name, SF Symbol icon, category, color, calendar, tags, notes, task priority defaults, menu bar, notifications |
| `WorkSession` | `@Model` | A live or finished session: timestamps, pauses, notes, tags, category, task priority, calendar references, sync status |
| `WorkLog` | struct | Read-only projection of a session for logs, analytics, notifications, and event notes |
| `TaskPriority` | struct | `isUrgent` and `isImportant`, with the four combinations derived ([ADR-022](../Decisions/ADR-022-task-priority-model.md)) |
| `WorkCategory` | enum | Category rules: `General` default, built-in names, normalization, case-insensitive identity and canonical spelling, the derived picker list, validation ([ADR-025](../Decisions/ADR-025-work-categories.md)) |
| `QuickTaskDraft` | struct | A session started without a template: name, category, priority, tags, notes, calendar |
| `MenuBarConfiguration` | struct | Six display modes, separator, icon-with-name (Name Only), visibility, icon/name/duration colors, background color; JSON `"version": 2` |
| `SymbolCatalog` | enum | The validated SF Symbols offered as template icons, with search (generated file): 367 category entries covering **314 distinct symbols** in 18 categories. `allNames` deduplicates, so the picker offers 314. |
| `TemplateSymbol` | enum | Icon rules: default and fallback symbols, 1.0 emoji → symbol map, normalization, and `displayName` that never returns emoji |
| `NotificationBehavior` | struct | Per-template start/finish notifications and reminder interval |
| `CalendarConfiguration` | struct | Sync on/off, default calendar, include notes/tags |
| `CalendarSyncStatus` | enum | `notSynced`, `synced`, `failed`, `eventMissing` |

### Persistence model

- Every entity has a stable `UUID` `id`. Calendar identifiers are stored as external references, never as identity.
- `WorkSession.templateID` is a plain UUID, not a relationship, and the session keeps a snapshot of the template's name, icon, and color. Deleting or renaming a template never alters recorded work.
- Value-type configurations (`MenuBarConfiguration`, `NotificationBehavior`, pause intervals) are stored as JSON `Data` with tolerant decoding, so new fields don't require schema migrations. `MenuBarConfiguration` writes `"version": 2`; version-less 1.0 data that showed the icon with Name + Duration decodes as Icon + Name + Duration.
- **Icons.** `WorkTemplate.icon` and `WorkSession.templateIcon` hold SF Symbol names. 1.0 stored emoji in the same properties; `PersistenceService.migrateLegacyIconsIfNeeded(defaults:)` converts them once at launch (UserDefaults flag `migration.sfSymbolIcons.v1`), changes only those values, rolls back on a failed save, and is skipped when the store is unavailable. Display code always goes through `TemplateSymbol.displayName` ([ADR-014](../Decisions/ADR-014-sf-symbols-template-icons.md)). A store written by the 1.0 code was verified to open, migrate, save, and reopen with the 1.1 models.
- All stored properties have defaults and there are no unique constraints, which keeps the model compatible with a future CloudKit store ([ADR-010](../Decisions/ADR-010-future-icloud-compatibility.md)).
- **Task priority.** `WorkTemplate` and `WorkSession` each store `isUrgent` and `isImportant` as non-optional `Bool`s defaulting to `false`; `TaskPriority` is the value type used everywhere else. The template's values are defaults, copied onto a session at start; the session's values are its own and are what `WorkLog` reports, so editing a template never rewrites recorded work ([ADR-022](../Decisions/ADR-022-task-priority-model.md)).
- **Categories.** `WorkTemplate.category` and `WorkSession.category` are non-optional `String`s defaulting to `"General"`. There is no category entity: the template's value is a default copied onto a session at start, the session's value is what `WorkLog`, analytics, filters, Calendar notes, and export use, and the picker list is derived from built-ins plus template values. `PersistenceService.renameCategory` renames on templates only; recorded sessions change only through `SessionService.edit` ([ADR-025](../Decisions/ADR-025-work-categories.md)).
- **Schema versions.** `CalendarTimeLoggerSchemaV1` (1.0, 1.1), `CalendarTimeLoggerSchemaV2` (1.2, adds the two priority attributes), `CalendarTimeLoggerSchemaV3` (1.3, adds `category`), and `CalendarTimeLoggerSchemaV4` (adds the `WorkCategoryRecord` entity, [ADR-027](../Decisions/ADR-027-stored-category-list.md)), with `.lightweight` stages V1 → V2, V2 → V3, and V3 → V4 in `CalendarTimeLoggerMigrationPlan`. Containers open `CalendarTimeLoggerCurrentSchema` (V4). No existing row is rewritten by a migration. **V1, V2, and V3 hold frozen copies of the 1.1, 1.2, and 1.3 models** (`Persistence/SchemaV1.swift`, `SchemaV2.swift`, `SchemaV3.swift`): a plan matches a store to a version by entity hashes, so an older version that points at the current models hashes identically to the current one, the store matches neither, and Core Data aborts the process with an Objective-C exception. `PersistenceService.open(url:)` is the single entry point for opening a store, so `StoreMigrationTests` can exercise each migration against real 1.1-, 1.2-, and 1.3-shaped files.
- **Categories.** `WorkCategoryRecord` is the stored list (stable `id`, `name`). Templates and sessions reference a category by name; sessions keep the name they were recorded with. `PersistenceService.reconcileCategories()` runs on open and before each category operation (built-ins for an empty list, General always, every template's category, case-only duplicates merged). `createCategory`, `renameCategory`, `migrateCategory`, and `deleteCategory(_:migratingTemplatesTo:)` each commit in one save and roll back on failure. `CategoryUsage.compute` derives template, work log, and open-session usage from live queries for the Categories sheet.
- The store is `Application Support/Calendar Time Logger/CalendarTimeLogger.store` inside the app sandbox container, with `cloudKitDatabase: .none`.
- **Deleted models.** Once a delete is saved, a model keeps its identity but loses its context, and reading an attribute that wasn't loaded is a fatal SwiftData error. `PersistentModel.isLive` (`modelContext != nil && !isDeleted`; `isDeleted` alone turns false again after the save) is checked wherever a model can outlive its row: `SessionService.delete`, `edit`, `reassignTemplate`, `finish` after its Calendar `await`, `CalendarService.sync` and `removeEvent`, and `PersistenceService.updateTemplate`, `duplicateTemplate`, and `deleteTemplate`. Deletes of an already-deleted item do nothing; edits of one throw `SessionError.workLogDeleted` or `PersistenceError.itemDeleted`.
- If the store can't be opened, `PersistenceService` falls back to an in-memory container and sets `storeError`. The UI shows the error and `SessionService` refuses to start sessions, so no work is recorded somewhere it would be lost.

Durations are not stored. They are computed from `startedAt`, `endedAt`, and pauses, and rounded to milliseconds to avoid floating-point drift in `Date` arithmetic.

## Services

All services are `@MainActor`. Those the UI observes are also `@Observable`.

### SessionService

Runs the session lifecycle using the state machine. Its clock is injectable (`now: () -> Date`), which makes the tests deterministic.

| Operation | Behavior |
| --- | --- |
| `start(template:)` | Refuses if storage is unavailable or a session is already open; saves immediately; snapshots the template; no Calendar access |
| `pause()` / `resume()` | Appends or closes a `PauseInterval`; reschedules or cancels reminders |
| `finish(at:)` | Closes any open pause, sets `endedAt`, saves, then calls `CalendarService.sync`, then sends notifications |
| `cancel()` | Marks the session cancelled with `endedAt`; never syncs |
| `changeTemplate(to:)` | Moves the open session to another template, keeping its timing |
| `reassignTemplate(of:to:)` | Moves a completed session to another template (identity and default tags follow), then updates its app-owned event if it has one |
| `appendNote(_:)`, `updateActiveSession(...)` | Edit the open session |
| `edit(_:with:)` | Validates and edits a completed session (times, notes, tags, calendar), trims pauses, re-syncs |
| `delete(_:removingCalendarEvent:)` | Deletes a finished session, optionally removing its owned event first |
| `resolveRecovery(_:)` | Resume, finish now, finish at the last heartbeat, or cancel a session found at launch |
| `recordHeartbeat()` | Stores `lastHeartbeatAt` (called every 60 s and before sleep) |
| `pauseForSystemSleep()` | Used when the "pause when my Mac sleeps" setting is on |

If a save fails, every mutation restores the in-memory values it changed and throws `SessionError.persistence`.

### CalendarService and CalendarProviding

`CalendarProviding` is the boundary around EventKit. `EventKitCalendarProvider` is the production implementation; the tests use `MockCalendarProvider`.

`CalendarService`:

- Tracks authorization and available calendars. It requests full access only when access was never requested.
- Resolves the calendar in this order: session override, template, global default, system default.
- Builds a `CalendarEventDraft`: the template name as title, the real start and finish times (or, with `CalendarEventTiming.nearestMinute`, each rounded to the nearest minute for the event only), human-readable notes, and an ownership URL. Recorded intervals are half-open `[start, end)` (`WorkInterval`), so a session ending at 11:00 and one starting at 11:00 are adjacent, not overlapping ([ADR-026](../Decisions/ADR-026-calendar-event-boundaries.md)).
- `applyEventTimingToExistingEvents` updates only synced sessions' existing app-owned events whose times differ from the current timing setting; it never recreates or duplicates events and is idempotent.
- `sync` finds the session's **owned** event, first by stored identifier (checking ownership) and then by searching ±1 day for the ownership URL, which covers Calendar changing an event's identifier. It updates that event if found and creates one otherwise. The outcome is stored on the session.
- `removeEvent` refuses to touch an event that doesn't carry the session's URL.
- `reconcile` re-links changed identifiers and marks sessions whose event was deleted as `eventMissing`. It runs at launch and whenever EventKit reports a store change.

### NotificationService and NotificationScheduling

`NotificationScheduling` wraps `UNUserNotificationCenter` (`UserNotificationScheduler` in production, `MockNotificationScheduler` in tests). A notification is delivered only when all of these allow it: the master switch, its category switch, the template's behavior (for start, finish, and reminders), and system permission. Permission is requested only when a start notification or reminder is actually wanted, or when the user chooses **Allow Notifications**.

Reminders are scheduled ahead at each upcoming multiple of *active* time (8 at a time). They are cancelled on pause and rescheduled on resume.

### MenuBarService, MenuBarFormatter, and AppInstancePolicy

`MenuBarFormatter` is pure. It turns a `MenuBarSessionSnapshot` into a `MenuBarPresentation`: `showsIdentity` (CTL) when no session is open; otherwise styled segments (icon and paused segments are SF Symbol names), an optional background color, or a generic symbol when the template hides itself; plus an accessibility label. With a background, automatic foregrounds become `HexColor.contrastingForeground`. `MenuBarService` builds the snapshot from the open session and its template's current configuration, so edits apply immediately. `isItemInserted` depends only on the Show CTL setting.

`AppInstancePolicy` decides which copy of the app keeps running (earliest launch, then lowest process ID).

```
SessionService ──▶ AppEnvironment (state) ──▶ MenuBarService / MenuBarFormatter ──▶ MenuBarLabel (MenuBarExtra)
```

In the app, `MenuBarLabel` draws the CTL identity (the template-image CTL mark, text, or clock symbol; see [ADR-019](../Decisions/ADR-019-app-icon-and-ctl-mark.md)). Popover sizes live in `MenuBarPopoverMetrics`. For a session it renders plain `Text` when there are no symbols or custom colors, a template `NSImage` for automatic colors with symbols, and a non-template `NSImage` (with the pill) when any color or background is custom ([ADR-015](../Decisions/ADR-015-persistent-ctl-menu-bar-item.md), [ADR-016](../Decisions/ADR-016-menu-bar-pill-and-symbol-segments.md)).

### Export

```
PersistenceService (completed sessions) ──▶ WorkLogExportService ──▶ WorkLogWorkbookBuilder ──▶ XLSXWriter ──▶ ZipArchiveWriter ──▶ .xlsx
                                                     │
                              ExportDestinationProviding (Save panel)  ·  ExportFileWriting (atomic write)
```

- `WorkLogExportService` filters completed sessions by `WorkLogExportScope` (all, current filter, today, this week, this month), builds the workbook **before** asking for a destination, then writes atomically. It returns `exported`, `cancelled`, or `failed(WorkLogExportError)` (no columns selected, invalid data, permission denied, disk full, write failed). It never modifies sessions. `preview(scope:filter:columns:limit:)` formats only the rows the export sheet shows.
- `WorkLogExportColumn` owns each column's header, width, description, cell, and preview text; `WorkLogColumnSelection` is the ordered, duplicate-free selection persisted in `SettingsStore.exportColumns`; `WorkLogExportPreset` supplies ready-made selections ([ADR-023](../Decisions/ADR-023-selectable-export-columns.md)).
- `WorkLogWorkbookBuilder` makes the Work Logs sheet (the selected columns, in order) and the Summary sheet (totals, by template, by task priority, daily, weekly).
- `XLSXWriter` writes SpreadsheetML with inline strings, date and duration serials in the calendar's time zone, a styles part, frozen header, and filter. `ZipArchiveWriter` writes the ZIP container with CRC-32 and DEFLATE ([ADR-018](../Decisions/ADR-018-xlsx-export.md)).

### WorkAnalytics and WorkLogQuery

These are pure functions over `[WorkLog]`: filtering and search (including by task priority and category), grouping by start day, per-template totals, per-category totals (one grouping pass, with template and priority totals nested per category, grouped by the recorded value), per-priority totals (all four combinations, zero-filled, plus overlapping urgent and important totals), per-template priority splits, range summaries, daily totals, and streaks.

### SettingsStore

An `@Observable` wrapper over `UserDefaults` (injectable for tests) for Calendar, notification, menu bar (including the CTL style), appearance, export, and general preferences (default template, daily goal, main window at launch).

### SessionClock

Publishes `now` once per second while a session is active (the timer runs in `.common` run-loop mode, so it keeps firing while menus are open). It only drives refresh; durations always come from timestamps.

## App layer

- **`AppEnvironment`** is the composition root and a singleton, so App Intents share the same services. It exposes UI actions that present errors instead of throwing, handles navigation state and the `calendartimelogger://` URL, and observes `NSWorkspace` sleep and wake notifications.
- **Navigation:** a single source of truth, `AppEnvironment.selectedSection` (an `AppSection`). The sidebar `List(selection:)` (work sections in `AppSection.primary`, then Settings and About in `AppSection.secondary`) and the detail view both read it, and so do the ⌘1–⌘5 commands and in-app links. `AppSection.id` is the section itself, so List rows match the selection type; a mismatched ID type makes rows unselectable. A `nil` sidebar selection keeps the current section (`AppSection.resolvedSelection`).
- **Launch and lifecycle:** `CalendarTimeLoggerApp.init` runs `SingleInstance` before `AppEnvironment` opens the store; a second copy activates the first and exits. `AppDelegate` keeps the app running when the last window closes. `LaunchWindowPresenter` (started from the menu bar label) opens the main window at launch when that setting is on, even if restoration remembered it closed.
- **Scenes:** `Window` (main window with a `NavigationSplitView`), `MenuBarExtra` (`.window` style, the permanent CTL item), and `Settings`. A DEBUG-only `Window` hosts the menu bar content for QA.
- **Commands:** a Session menu (Start Work… ⌥⌘S, Quick New Task… ⌥⌘N, Start Template ⌃⌘1–9, Pause/Resume ⌥⌘P, Finish Work ⌥⌘F, Change Category and Priority…, Change Template, Cancel Session…, which confirms with an alert whose default button is Keep Working), section switching (⌘1–⌘5), and File › Export Work Logs… (⇧⌘E).
- **Work Logs filter state** (`WorkLogFilterState`) lives on `AppEnvironment` so the export sheet can offer Current Filter.
- **Edit and delete ownership.** A view never deletes the model it is rendering. `WorkLogsView` owns the work log edit sheet and delete confirmation, and `TemplatesView` owns the template delete confirmation; the details pane, editor, row shortcut menus, and the Delete command only request them. Requests carry identifiers (`WorkLogAction`, `TemplateDeletion`), not models. Confirming deselects the item first, then deletes it by identifier, and restores the selection if the delete fails. Views that hold a model (`WorkLogDetailView`, `WorkLogEditSheet`, `TemplateEditorView`, the menu bar start form) render nothing once it is no longer live. The 1.3 details pane owned its own confirmation and read the deleted work log while the confirmation closed, which terminated the app.
- **Export UI:** `ExportWorkLogsView` (scope, Summary option, session count, column selection with drag-to-reorder, presets, and a preview) and `SavePanelDestination` (`NSSavePanel`).
- **Priority UI:** `TaskPriorityPicker`, `PriorityChips`, `PriorityMarkers`, `PriorityValueRows`, and `TaskPriorityCard` in `UI/Components/PriorityControls.swift`; `StartSessionSheet`, `QuickTaskSheet`, and `ChangeTaskPrioritySheet` in `Features/Sessions/StartWorkSheets.swift`; compact inline equivalents in the menu bar popover.
- **Recovery** appears inline on the Dashboard and in the menu bar popover rather than as a launch-time sheet ([ADR-012](../Decisions/ADR-012-recovery-and-sleep.md)).
- **App Intents:** `StartWorkIntent` (with a `TemplateEntity` parameter shown with its SF Symbol), `PauseResumeWorkIntent`, `FinishWorkIntent`, and an `AppShortcutsProvider`.

## Platform configuration

| Setting | Value |
| --- | --- |
| Target / scheme | `calender_time_logger` (internal identifier kept from the original project) |
| Product name | `Calendar Time Logger.app`, module `CalendarTimeLogger` |
| Bundle identifier | `abirbarman.calender-time-logger` |
| Deployment target | macOS 27.0, `SUPPORTED_PLATFORMS = macosx` |
| Swift | Swift 6 language mode (app and package), app default actor isolation `MainActor` |
| Icon | Generated by `scripts/generate-app-icon.swift` into `Resources/AppIcon.icns` (the app icon, `CFBundleIconFile`) plus `AppIcon.appiconset`, `BrandLogo.imageset`, and `CTLWordmark.imageset` for the installer, the in-app logo, the menu bar CTL mark, the welcome screen, and the docs, all from the original `logo.png` glyphs |
| Packaging | `scripts/package-dmg.sh` → `dist/Calendar-Time-Logger-v<version>.dmg` |
| Sandbox | App Sandbox on; Calendars resource access on; user-selected files read/write (`ENABLE_USER_SELECTED_FILES = readwrite`, used only by the export Save panel); no network or other entitlements |
| Version | `MARKETING_VERSION` 1.1.0, `CURRENT_PROJECT_VERSION` 3 |
| Hardened runtime | On |
| Info.plist | Generated, merged with `Resources/Info.plist` (URL scheme `calendartimelogger`) |
| Usage descriptions | `NSCalendarsFullAccessUsageDescription` |

## Error handling summary

| Failure | Result |
| --- | --- |
| Calendar access denied, restricted, or write-only | Session saved; status `failed` with instructions for System Settings |
| Calendar deleted or read-only | Session saved; status `failed`; no fallback to another calendar |
| Event save fails | Session saved; status `failed`; retry available |
| Event deleted in Calendar | Status `eventMissing`; can be re-added |
| Event not owned | Never modified; a new owned event is created on sync; removal refused |
| Notification permission denied | Notifications skipped silently; Settings shows the status |
| Store can't open | In-memory fallback, error banner, starting sessions refused |
| Save fails during a transition | In-memory changes rolled back; error shown |
| Invalid transition | `SessionError.invalidTransition` / `noActiveSession`; nothing changes |
| Item deleted before an action on it | Deleting again does nothing; editing, moving, or saving throws `workLogDeleted` / `itemDeleted`; Calendar sync is skipped |
| Legacy or unknown icon value | Shown as a mapped or fallback SF Symbol; converted once at launch |
| Export: no columns selected | `noColumnsSelected`; the Export button is disabled and the sheet explains why; the Save panel never opens |
| Export: Save panel cancelled | Nothing written; the export sheet stays open |
| Export: data can't be encoded (for example non-finite numbers, out-of-range dates) | `invalidData`; reported before the Save panel; nothing written |
| Export: no permission, read-only volume, disk full, other write error | `permissionDenied`, `diskFull`, or `writeFailed` with recovery text; atomic write leaves no partial file; work logs unchanged |
| Second copy of the app launched | It activates the running copy and exits before opening the store |
