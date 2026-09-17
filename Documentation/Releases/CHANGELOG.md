# Changelog

All notable changes to Calendar Time Logger are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](VERSION.md).

## [Unreleased]

Nothing yet.

## [1.4.0] — 2026-09-17

Template editor layout, category management, clearer task priority, and Calendar event boundaries; a regression audit of every Edit and Delete action in the main window and the menu bar; and the release documentation, license, and installer for 1.4.0.

### Release

- **Version 1.4.0, build 6.** 1.3.0 (5) was already installed with a version 3 store, and this release changes the schema to version 4, so it gets a new MINOR version and build number ([VERSION.md](VERSION.md)).
- **MIT License.** A [LICENSE](../../LICENSE) file (copyright 2026 Abir Barman) replaces the previous "all rights reserved" statement.
- A new `dist/Calendar-Time-Logger-v1.4.0.dmg` built by `scripts/package-dmg.sh`; the stale 1.1.0 and 1.3.0 images were removed from `dist/`. Development-signed, not notarized.

### Improved

- **About** (Settings and the main window) says **Developed by Abir Barman** and links to [abirbarman.com](https://abirbarman.com).
- The Export settings pane's column description now mentions category and task priority.

### Documentation

- **README rewritten** for a public release: installation first, features, a seven-image screenshot set, Getting Started, one section per area (templates, categories, task priority, menu bar, Calendar with the event boundary example, Work Logs, Analytics, Excel export, settings), development, testing, release, documentation, license, and author.
- **Screenshots recaptured** from the 1.4.0 DEBUG demo build with consistent window framing: `01-dashboard`, `02-dashboard-active-session`, `05-quick-new-task`, `06-work-logs`, `07-work-log-detail`, `09-analytics-overview`, `10-analytics-category`, `11-menu-bar-idle`, `12-menu-bar-active`, `13-work-completed`, `14-excel-export`, `15-installation` (from the 1.4.0 DMG), `16-startup`, `settings`, and `work-log-sync-failed`. New: `settings-calendar.png` (Event Times). The README uses seven screenshots instead of ten.
- Settings: the Export pane's column count (16 of 17) and Summary sheet contents were corrected, and About describes the author line. Getting Started, the User Guide index, VERSION, RELEASE, and CLAUDE.md were updated for 1.4.0 and the license.

### UI

- **The New Template sheet no longer clips.** It had a fixed 860 x 760 frame, but a sheet can't be larger than its window, so in a smaller window the content was cut off on both sides and the sections below Basic Information were squeezed. The sheet now fits its window, sections scroll, and **Cancel** and **Create Template** (or **Revert** and **Save Changes**) stay in a footer that is always visible.
- **Task Priority sits directly under Basic Information** in the template editor, with a short explanation of template defaults. **Color & Appearance** is now **Appearance**.
- In a narrow editor, **Start Work**, **Duplicate**, and **Delete** move under the template name instead of truncating it, and the icon and color rows wrap instead of pushing cards past the edge.
- **Icon picker:** the category chips wrap so every category is visible; the grid is wide enough that the last column is never under the scroller; the picker opens scrolled to the current icon; <kbd>Return</kbd> in the search field picks the first match.
- **Work Logs rows** switch to two lines when the list is narrow, so the name, priority, and duration are never squeezed out.

### Categories

- **Add Category**, **Rename…**, **Move Templates…**, and **Delete…** in Templates › Categories ([ADR-027](../Decisions/ADR-027-stored-category-list.md)). Each row shows the templates and work logs using the category and marks the category of the session in progress.
- **Categories are stored with a stable identity.** A category exists until you delete it, even before any template uses it, and renaming keeps the same category. The built-in categories can be deleted; **General** can't be renamed or deleted.
- **Deleting a category templates use** opens a sheet that lists the templates, the work logs recorded in it, and the session in progress, and moves the templates to the category you choose in the same step as the delete. If anything fails, nothing changes.
- **History is never rewritten.** Renaming, moving, or deleting a category changes templates and future sessions only; recorded work logs and the session in progress keep their category. Edit Entry shows a deleted category as "*Name* (deleted)".
- **Category menus update immediately** everywhere, including the menu bar, and follow a rename or delete while a template editor is open. **New Category…** saves the category straight away.
- Case-insensitive duplicate names and blank names are refused with an explanation, and a repeated **Add**, **Move**, or **Delete** can't act twice.

### Task Priority

- **Yes is visible at a glance.** Beside each No / Yes control, a Yes value shows a filled, colored symbol and a bold label. Priority chips use filled symbols, stronger contrast, and a hairline border, and stay legible on a selected row.
- The template editor's Task Priority header and title show worded **Urgent** / **Important** badges (or **Neither**).
- **Start Work** labels the section **Session Priority**, says whether the values are the template's defaults or changed for this session only, and offers **Use Template Defaults**. Changing them never changes the template.
- The **menu bar popover** shows worded Urgent and Important badges under the running session.
- **Edit Entry** uses the same priority control and says it changes only that recorded session.

### Calendar

- **Calendar Event Boundaries** ([ADR-026](../Decisions/ADR-026-calendar-event-boundaries.md)). Recorded times are half-open intervals: a session ending at 11:00 and one starting at 11:00 are adjacent, never overlapping, and no minute is ever added or removed.
- **Settings › Calendar › Event Times:** **Keep exact times** (default) writes each session's exact start and finish; **Round to the nearest minute** rounds only the Calendar event, so back-to-back sessions stack cleanly while Work Logs, Analytics, and exports keep exact times. **Update Existing Events…** applies the choice to events the app already created, only where their times differ, without recreating or duplicating anything.

### Fixed

- **Editing a work log's time could create a hidden overlap.** Edit Entry's time pickers show hours and minutes but kept the old seconds, so changing a start of 11:02:15 to 11:00 saved 11:00:15, overlapping a session that ended at 11:00 and making Apple Calendar draw both events side by side. A time you change is now stored as that whole minute, and the sheet names any work logs the new times overlap.

### Reliability

- Category pickers resolve renamed and deleted categories instead of holding a stale selection.
- Category and priority actions were checked end to end in the main window and the menu bar: create, rename, move, delete, start, pause, resume, and finish, including rapid repeated clicks. See the verification log in [TESTING.md](../Testing/TESTING.md).
- Tests for category management (scenarios A–F), a 1.3 store migration, the Calendar boundary matrix, event timing, and minute editing: 216 tests in 23 suites.

### Changed

- The persisted schema is version 4: a new `WorkCategoryRecord` entity. The 1.3 models are frozen in `CalendarTimeLoggerSchemaV3`, and the V3 → V4 migration is lightweight. On first launch the category list is filled from the built-ins and the categories your templates use; no template or work log is rewritten. Downgrading to 1.3.0 afterwards is not supported.

### Documentation

- New ADRs: [ADR-026](../Decisions/ADR-026-calendar-event-boundaries.md) and [ADR-027](../Decisions/ADR-027-stored-category-list.md); ADR-025 is partly superseded.
- Updated User Guide: Categories, Task Priority, Templates, Calendar, Settings, and Work Logs. Updated Architecture, Development (`-demoState newTemplate`), Testing, and README.
- Recaptured `03-templates.png`, `04-template-editor.png`, `08-calendar.png`, `symbol-picker.png`, and `start-work.png` from the DEBUG demo build.

---

The Edit and Delete regression audit:

### Fixed

- **Deleting a work log quit the app.** Confirming **Delete** in the Work Logs details pane terminated Calendar Time Logger (a SwiftData "backing data was detached" fatal error): the pane owned the confirmation and read the deleted work log while the confirmation closed. The work log was deleted, but the app quit. The confirmation now belongs to the Work Logs list, which deselects the work log before deleting it; nothing reads a deleted work log afterwards.
- **Deleting a template could quit the app the same way**, for the same reason. Template deletion now follows the same pattern from the Templates list.
- **Session › Cancel Session discarded the session without asking.** The Dashboard and menu bar confirm first; the Session menu now does too, with **Keep Working** as the default button.
- **Edits and Calendar syncs could act on a work log deleted in the meantime**, for example one deleted while the Calendar permission prompt was still up after Finish Work. Editing, moving, retrying, or deleting an already-deleted work log or template is now refused or does nothing, and never writes a Calendar event for it.
- **The menu bar's Start with Category and Priority form had no way out** if its template was deleted from the main window while the form was open. The popover now returns to the template list.
- **A long template name widened the template editor's Menu Bar Preview** over the Basic Information card, covering the Name field. The preview now shortens the name in the middle and keeps the duration visible.
- **Tags in the Work Logs details pane broke mid-word** (for example "#re-search"). Tags now wrap as whole chips.
- A failed template delete is rolled back instead of being left pending in the database.

### Added

- **Edit Entry…** and **Delete…** on each Work Logs row's shortcut menu, and **Edit Template** and **Delete…** on each Templates row's. They act on the row clicked, even when another is selected.
- <kbd>Delete</kbd> (**Edit › Delete**) asks to delete the selected work log or template.
- The template delete confirmation says when the template belongs to the session in progress, and that the session keeps running.
- VoiceOver names the item on the Work Logs **Edit** and **Delete** buttons and the template editor's **Delete** button (for example "Delete Research work log").
- DEBUG demo mode: `-demoPersistentStore` keeps demo data and settings on disk so a relaunch can verify persistence, and `-demoResetStore` starts it over.
- Tests for edit and delete lifecycles: repeated deletes, acting on deleted work logs and templates, deleting a work log while Calendar asks for access, deleting the template of a running session, and edits and deletes surviving a relaunch without changing unrelated work (193 tests in 21 suites).

## [1.3.0] — Unreleased

Categories for templates and sessions, category analytics, category-aware Work Logs, and a Category export column.

### Added

- **Template categories** ([ADR-025](../Decisions/ADR-025-work-categories.md)). Every template has a mandatory category, chosen under **Basic Information › Category**. Six are built in (Development, Education, Research, Content, Design, General); **New Category…** names another in place. Names are up to 40 characters and case-insensitive, so `research` joins **Research**. The default templates are now in Development, Education, Research, Content, and Design.
- **Manage Categories** (the folder button in the Templates list): each category with the number of templates using it, and **Rename…**, which renames it on every template and merges onto an existing name. Unused custom categories disappear from the list on their own.
- **A category on every session.** A session takes its template's category when it starts, and keeps it: editing, renaming, or changing a template's category never changes work already recorded. The **Start Work** sheet, the menu bar's **Start with Category and Priority…**, and **Quick New Task** (sheet and popover) let you choose the category for that session; quick tasks start in General.
- **Change Category and Priority** during a session, from the Dashboard, the Session menu, and the menu bar popover (which shows the category menu inline).
- **Categories in Work Logs.** Each row shows the category under the template name, the inspector has a **Category** row, the edit sheet can correct it, the filter menu adds **Category**, and search matches category names. **Change Template** moves an inherited category to the new template and keeps one chosen for the session.
- **Work by Category in Analytics**: a bar chart with each category's share, a row per category with sessions, share, and time, and **Templates and Task Priority by Category**, which lists the templates and priority combinations inside each category. Everything follows the selected date range, and an empty range shows **No category data yet**.
- **Category in Excel export**: a selectable **Category** column (included by default, after Template), a **Category Analysis** preset (Date, Template, Category, Duration, Urgent, Important), and a **Work by Category** block on the Summary sheet.
- **Category in Calendar event notes**: a `Category:` line. Event titles are unchanged.
- The category is shown on the Dashboard session card and in Today's Work, in the menu bar popover, and in the Work Completed confirmation.
- Tests for categories (names, validation, renaming, sessions, history preservation, live changes, quick tasks, template changes, filtering, analytics including date ranges, midnight, renamed categories, and a real exported workbook), a migration test for a store written by 1.2, and a **simulated 30-day regression** that drives a month of realistic work through the real services against an isolated on-disk store — 184 tests in 20 suites.

### Changed

- The persisted schema is version 3: `category` was added to templates and sessions as a non-optional value defaulting to `General`. Existing templates and work logs migrate to **General** and keep every other value; nothing is rewritten. The 1.2 models are frozen in `CalendarTimeLoggerSchemaV2` so the migration can identify a 1.2 store.
- The template editor's **Basic Information** card adds Category, and its header shows the template's category.
- Analytics adds Work by Category above Task Priority.
- Default exports now include Category after Template, so the columns after Template have moved one place right. The export sheet lists 17 columns.
- Change Task Priority is now **Change Category and Priority** in the Session menu, the Dashboard's session actions menu, and the menu bar popover; **Start with Priority…** in the menu bar is **Start with Category and Priority…**.
- The template and Work Logs search fields also match categories.
- DEBUG demo mode seeds 30 consecutive days of work with categories, uses sample calendars instead of reading the real calendar list, and no longer shows a Calendar sync warning unless launched with `-demoSyncFailure`. `-demoSettingsPane` opens a specific Settings pane.
- **The CTL brand uses the original logo's letterforms everywhere.** The app icon, the in-app logo, and the menu bar CTL mark were drawn with a system font; they now use the white "CTL" glyphs from the original `logo.png`, lifted as a mask and only ever scaled down, centered on black. The wordmark is larger in the icon (70% of the tile, 82% at 16 and 32 px) and legible at every size.
- **The welcome screen has a CTL brand header**: the original wordmark and the product name on black, in both light and dark appearance, above the welcome content.
- **The installer is dark**: the CTL wordmark and product name on a black background, the app and Applications with the accent arrow, and each Finder label on a light plate so it stays readable (Finder draws labels in dark text). The previous light tray and graphite header are gone.

### Documentation

- **README restructured** for a first-time visitor: installation comes first (the disk image, the first-launch security check for a build that isn't notarized, and building from source with verified commands), followed by an overview, a feature table, a short screenshot gallery, the core workflow, one short section per area, requirements, development, testing, building a release, documentation, privacy, troubleshooting, known limitations, contributing, and license.
- **User Guide landing page** with a "find your answer" table, and a new [FAQ](../User%20Guide/FAQ.md). Getting Started now covers installation, the security check, upgrading, and the new welcome screen; Sessions gains Start Work, Quick New Task, and active-session screenshots.
- **All screenshots recaptured** from the rebuilt app with CleanShot X after the branding change, including `15-installation.png` (the installer) and `16-startup.png` (the welcome screen), which replace `dmg-installer.png` and `onboarding.png`. `menu-bar-paused.png` was removed: the paused menu bar item couldn't be captured from the live menu bar, and the page now describes it in words.

- New User Guide page: [Categories](../User%20Guide/Categories.md). Templates, Sessions, Task Priority, Dashboard, Menu Bar, Work Logs, Analytics, Exporting Data, Getting Started, and Troubleshooting were updated.
- New testing document: [30-Day Regression](../Testing/30-Day%20Regression.md).
- New ADR: [ADR-025](../Decisions/ADR-025-work-categories.md).
- New screenshots captured with CleanShot X from the 1.3.0 DEBUG demo build, numbered `01-dashboard.png` through `14-excel-export.png`, plus updated Start Work, Sync Failed, and menu bar form captures; screenshots of screens that changed were replaced.

### Fixed

- **The DMG had no volume icon.** `scripts/package-dmg.sh` built `.VolumeIcon.icns` but the file never reached the finished image (the 1.1.0 disk image had the same gap), so the mounted volume showed a generic disk. The icon is now added after Finder lays out the window, the volume is marked as having a custom icon, and a missing icon fails the build.

### Known Limitations

- Renaming a category does not rename it in recorded work logs; Analytics shows the old and new names as separate rows for the period before and after the rename. Individual work logs can be corrected with Edit Entry, but there is no bulk change for history.
- There is no custom date range in Analytics; category figures follow the existing ranges (Today, This Week, Last 7 Days, This Month, Last 30 Days).
- Downgrading to 1.2.0 after 1.3.0 has migrated the store is not supported.

## [1.2.0] — Unreleased

Task priority tracking for every session, Quick New Task, priority analytics, and an Excel export whose columns you choose.

### Added

- **Task priority on every session.** Work is classified as **Urgent** (Yes/No) and **Important** (Yes/No). Both values are mandatory and always have a value; there is no unset state. The four combinations — Urgent + Important, Urgent + Not Important, Not Urgent + Important, Not Urgent + Not Important — are derived from the two values, so analytics and filtering can ask either question on its own ([ADR-022](../Decisions/ADR-022-task-priority-model.md)).
- **Task Priority in the template editor.** Every template sets the defaults that sessions started from it begin with. Existing templates keep every other setting and start at Not Urgent, Not Important.
- **Start Work sheet** (⌥⌘S, the Dashboard's Start Work button, the toolbar's New Session). It shows the template and its task priority before the timer starts, so the values can be changed for this session only. Starting a template directly — from the template menu, a Recent Templates tile, the Session menu, the menu bar list, or Shortcuts — still starts immediately with that template's defaults.
- **Quick New Task** (⌥⌘N): name the work, set Urgent and Important, and start, without creating a template. Available from the Dashboard (Quick Actions and beside Start Work), the Session menu, and the menu bar (⌘T inside the popover). Quick tasks appear in Work Logs, analytics, Calendar, and export like any other session.
- **Change Task Priority during a session**, from the Dashboard session card, its actions menu, Quick Actions, the Session menu, or the menu bar popover. The Work Log records the values the session ends with.
- **Priority in Work Logs.** Rows show Urgent and Important chips (symbols when a row is narrow), the detail pane has a Task Priority section with both values in words, the edit sheet can correct them, and the filter menu adds Urgent, Important, Urgent + Important, and Neither.
- **Task Priority analytics.** Analytics now has one date range for the whole screen (Today, This Week, Last 7 Days, This Month, Last 30 Days) and a Task Priority section: a card for each of the four combinations with time, share, and session count; a bar chart; total time on urgent and on important work (which overlap, and say so); and a By Template breakdown. Summary tiles show total work, sessions, average session length, and the streak for the selected range.
- **Selectable Excel export columns** ([ADR-023](../Decisions/ADR-023-selectable-export-columns.md)). The export sheet lists all 16 available columns, with checkboxes, drag-to-reorder for the included ones, Select All / Deselect All, presets (Basic, Detailed, Priority Analysis, Everything), and a live preview of the first rows. The chosen columns and their order are remembered. Exporting with no columns selected is refused with an explanation instead of writing an empty file.
- **Urgent and Important as export columns**, selectable independently, written as Yes / No. A `Task Priority` column (the combination in words) is available and off by default. The Summary sheet gains **Work by Task Priority**, with the four combinations plus overlapping urgent and important totals.
- **Priority in Calendar event notes**: `Urgent: Yes · Important: No`. Event titles are unchanged.
- **The CTL mark in the menu bar**: white `CTL`, optically centered on a black rounded plate, as in the app logo. It is the new default for the idle menu bar item; the previous outline is still available as CTL Outline, alongside CTL Text and the clock symbol (Settings › Menu Bar).
- Regression tests for task priority (templates, sessions, overrides, live changes, quick tasks, migration, filtering, analytics, and Calendar notes) and for export columns (selection, order, presets, refusal of an empty selection, the Summary sheet's priority block, and the preview) — 159 tests in 18 suites, including a store-migration suite that opens a store written by the 1.1 models.

### Changed

- **The app icon is now flat and fills its tile**: a solid black body with the white CTL wordmark and nothing else. The hairline edge, the baked drop shadow, the graphite gradient, and the accent bar are gone. The icon also ships as `AppIcon.icns` instead of an asset-catalog icon, because macOS 26 and later composite an asset-catalog app icon onto a gray compatibility plate — the light border that appeared around the icon in Launchpad ([ADR-024](../Decisions/ADR-024-flat-icns-app-icon.md)). The in-app logo (About, onboarding, menu bar popover footer) uses the same flat mark in its rounded form.
- The persisted schema is version 2: `isUrgent` and `isImportant` were added to templates and sessions as non-optional values defaulting to `false`. The migration is lightweight — existing templates and work logs keep every other value and are not rewritten.
- Default exports now include Urgent and Important after Template, so column positions after Template have moved.
- Analytics replaced its Today / This Week / Streak tiles and its chart-only range picker with one range for the whole screen.
- The Dashboard's Start Work button opens the Start Work sheet instead of starting immediately; its attached menu still starts any template directly.

### Documentation

- New User Guide page: [Task Priority](../User%20Guide/Task%20Priority.md). Sessions, Templates, Dashboard, Work Logs, Analytics, Exporting Data, Menu Bar, and Settings were updated, with new screenshots from the DEBUG demo build.
- New ADRs: [ADR-022](../Decisions/ADR-022-task-priority-model.md) and [ADR-023](../Decisions/ADR-023-selectable-export-columns.md).
- **A User Guide for people using the app**, in `Documentation/User Guide/`: Getting Started, App Overview, Sessions, Dashboard, Templates, Menu Bar, Work Logs, Calendar, Analytics, Notifications, Exporting Data, Settings, and Troubleshooting. Each page documents only implemented behavior, carries Previous / Up / Next links, and uses screenshots captured from the DEBUG demo build.
- **A rewritten README** as a public project entry point: hero screenshot, overview with a worked timeline, features, how it works, a curated screenshot section, requirements, installation, getting started, links into the User Guide and the developer documentation, privacy, architecture, development, testing, release, roadmap, and license.
- **New screenshots** captured from the current 1.1.0 build: idle and active Dashboard, Work Logs with its inspector, a work log detail in both synced and Sync Failed states, the icon picker, Analytics, Settings, the completion confirmation, the export sheet, the welcome screen, the idle and active menu bar popovers, and the menu bar item idle, working, and paused.
- `Documentation/README.md` now indexes the User Guide alongside the contributor documentation.
- `DOCUMENTATION_RULES.md` gives the User Guide an owner and an update trigger, requires a User Guide page for every new user-visible feature, and requires screenshots to be checked for personal data (the demo build supplies demo work data, but still reads the real calendar list when the app has Calendar access).

### Fixed

- **The documented size of the icon picker was wrong.** README, ARCHITECTURE, PRODUCT_REQUIREMENTS, and the 1.1.0 changelog entry said the picker offers 367 symbols. `SymbolCatalog` holds 367 *category entries*, but symbols that appear in more than one category are deduplicated, so the picker offers **314** distinct symbols — the number the picker itself displays. ADR-014 already said "entries" and is unchanged.
- `scripts/check-doc-links.sh` treated `%20` literally, so a link to a path containing a space was reported as broken. It now decodes `%20` before checking that the file exists.

## [1.1.0] — Unreleased

A redesign of the main window, menu bar, and completion flow, with SF Symbols throughout, a permanent CTL menu bar item, and Excel export.

### Added

- **SF Symbols template icon system.** Templates use SF Symbols instead of emoji. The icon picker offers 314 distinct symbols in 18 categories (Development, Education, Research, Writing, Design, Business, Communication, Productivity, Files, Media, Finance, Health, Travel, Tools, System, People, Objects, Nature), with search and category filters. Every name is validated against the SF Symbols installed with macOS.
- **Persistent CTL menu bar item.** Calendar Time Logger's menu bar item is present whenever the app runs, whether or not you're working, and is removed when the app quits. When idle it shows CTL as a badge (default), text, or clock symbol (Settings › Menu Bar). During a session it shows the running template, and returns to CTL when the session finishes or is cancelled.
- **Template-specific menu bar appearance**, with a new **Icon + Name + Duration** display mode (six modes in total) and per-template icon, name, and duration colors.
- **Menu bar background color.** A template can draw its menu bar item on a colored pill. Automatic text colors switch to white or black to stay legible on it.
- **Excel workbook export** (File › Export Work Logs…, ⇧⌘E; Work Logs toolbar; Dashboard Quick Actions; Settings › Export). Choose All Work Logs, Current Filter, Today, This Week, or This Month, then save through the Save panel. The **Work Logs** sheet has one row per completed session with date, start and end times, duration, active and paused durations, template, tags, notes, calendar, Calendar event status and identifier, and session status. Dates and durations are real Excel values. An optional **Summary** sheet has totals, work by template, and daily and weekly totals.
- **A new app icon**, drawn from vector sources at every size and following the macOS icon grid, so Finder, the Dock, Spotlight, About, and the installer no longer show it on a gray compatibility plate. The same generator produces the About and onboarding artwork.
- **DMG installer**: `scripts/package-dmg.sh` produces a verified, checksummed `dist/Calendar-Time-Logger-v<version>.dmg` with a branded background, the app, and an Applications shortcut.
- **Calendar event appearance** section in the template editor. It shows the color of the calendar the template's events will use and explains that Apple Calendar colors events by calendar (see Known Limitations), with **Match Icon Color to Calendar**.
- **Change Template** for a completed work log. It moves the session to another template and updates its Calendar event.
- **Duplicate** for templates.
- Dashboard **Today's Progress** (per-template ring and daily goal), **Quick Actions**, and a per-session Today's Work list.
- Settings: default template for Start Work, daily goal, "Show the main window when Calendar Time Logger opens" (honored even when the window was closed at the last quit), CTL style, and export defaults (scope, Summary sheet, show in Finder). Settings and About are also in the sidebar.
- Only one copy of Calendar Time Logger runs at a time; a second copy activates the first and quits.
- Regression tests for symbols, icon migration, menu bar lifecycle and appearance, completed-session template changes, settings, and Excel export (131 tests in 15 suites).

### Changed

- **A redesigned, narrower menu bar popover** (288 pt): stronger “Ready to work” hierarchy, larger template rows with a chevron menu (Start Work, Edit Template…), SF Symbols in the primary text color, right-aligned keyboard shortcuts, and one place for its sizes (`MenuBarPopoverMetrics`).
- The idle menu bar item now shows the **CTL mark**: “CTL” in an outlined rounded square with a chevron, drawn as a template image so macOS tints it for light, dark, and highlighted menu bars.
- **Documentation moved into `Documentation/`**, grouped by purpose (Architecture, Decisions, Design, Development, Product, Releases, Testing). Only `README.md` and `CLAUDE.md` remain at the repository root, and `scripts/check-doc-links.sh` now enforces that along with link checking.
- **A rewritten README** with an overview, screenshots, installation, usage, architecture, and documentation links, plus a new `CLAUDE.md` for contributors.
- **Redesigned** Dashboard, Work Logs (list plus detail inspector with Edit Entry, View in Calendar, Change Template, and Delete), completion confirmation, Templates (card-based editor with live menu bar preview), menu bar popover, and Settings, with a purple accent.
- Existing templates and work logs that use emoji icons are converted to SF Symbols once, at launch. Unknown emoji become a generic symbol. Only the icon value changes.
- Menu bar configurations saved by 1.0 keep their look: Name + Duration with the icon becomes Icon + Name + Duration.
- The paused indicator in the menu bar is now the `pause.fill` symbol. Notifications no longer include an icon.
- Closing the main window keeps Calendar Time Logger running in the menu bar.
- New sandbox entitlement: user-selected files (read and write), used only for saving exports.
- Add Note now uses the `note.text.badge.plus` symbol.
- Version 1.1.0 (build 3).

### Fixed

- **Sidebar navigation did nothing when clicked.** Dashboard, Templates, Work Logs, Calendar, and Analytics looked inactive, showed no selection, and clicks didn't change the screen. Each sidebar row was identified by a `String` while the selection was an `AppSection`, so the list could never match a row to the selection. Rows are now identified by `AppSection` itself. Clicking, the arrow keys, and ⌘1–⌘5 all move the highlight and the screen together.

### Documentation

- New: `Documentation/README.md` (index), `Documentation/Design/BRANDING.md` (icon, CTL mark, menu bar, installer artwork), and screenshots captured from the demo build.
- New decision records: [ADR-019](../Decisions/ADR-019-app-icon-and-ctl-mark.md) (app icon and CTL mark), [ADR-020](../Decisions/ADR-020-dmg-packaging.md) (DMG packaging), [ADR-021](../Decisions/ADR-021-documentation-structure.md) (documentation structure).

### Known Limitations

- **Per-event Calendar colors aren't possible.** EventKit has no event color; Apple Calendar draws each event in its calendar's color. Choose a calendar with the color you want for each template ([ADR-017](../Decisions/ADR-017-calendar-event-color-limitation.md)).
- After 1.1.0 converts a store's icons, Calendar Time Logger 1.0 would show symbol names as text if run against the same data.
- A text field in the main window can have keyboard focus when the window opens (standard AppKit first-responder behavior).
- The single-instance guard is unit tested but wasn't exercised against a second non-demo copy during development, to avoid opening the real store twice.
- Builds are signed with a personal Apple Development certificate and aren't notarized, so the DMG is meant for the developer's own Mac. Other Macs need Developer ID signing and notarization.
- The installer background uses a light tray behind the icons because Finder draws file labels in dark text over custom backgrounds, whatever the system appearance.
- The known limitations of 1.0.0 below still apply.

## [1.0.0] — Unreleased

First version of Calendar Time Logger for macOS 27.

### Added

- **Live work sessions:** Start, Pause, Resume, Finish Work, and Cancel, backed by an explicit state machine that rejects invalid transitions.
- Timestamp-based timing with separate wall-clock, paused, and active durations.
- One open session at a time, with **Change Template** for a running session and timestamped **Add Note**.
- **Work Templates** with name, emoji icon, color, calendar, tags, notes, notification behavior, and menu bar configuration; create, edit, delete, reorder, validation; five default templates on first launch.
- **Menu bar item** (`MenuBarExtra`) with Name + Duration, Name Only, Duration Only, Icon + Duration, and Icon Only modes; per-template separator, visibility, and icon/name/duration colors; a pause glyph when paused; popover with full session controls, Today's Work, and navigation.
- **Apple Calendar sync** (EventKit): full-access permission flow, calendar discovery, global default and per-template calendars, per-session override, event creation on Finish Work, event updates after edits, optional event removal on delete, reconciliation of deleted or re-identified events, and ownership checks through a `calendartimelogger://session/<id>` event URL.
- Calendar failure handling that always keeps the work log, with Sync Failed and Event Missing states, retry, and a Sync Issues list.
- **Work Logs** grouped by day with search, date/template/tag/Calendar-status filters, and an inspector for editing times, notes, tags, and calendar.
- **Dashboard** with the current session, recovery card, Ready to work with recent templates, and Today's Work.
- **Analytics** (Swift Charts): Today, This Week, and Streak tiles; this week by template; daily active work for 7 or 30 days.
- **Notifications:** session started, active-time reminders, work completed (optionally with today's total), and Calendar sync failures, each controlled globally and per template.
- **Recovery** of sessions left open by a quit or crash: resume, finish now, finish at the last known running time, or cancel.
- Optional automatic pause when the Mac sleeps.
- **Settings:** General (open at login, pause on sleep), Templates, Calendar, Notifications, Menu Bar, Appearance (System/Light/Dark, accent, density), Privacy, About.
- First-launch onboarding.
- Keyboard commands: Session menu (Start Work ⌃⌘1–9, Pause/Resume ⌥⌘P, Finish Work ⌥⌘F) and ⌘1–⌘5 section switching.
- **App Intents:** Start Work, Pause or Resume Work, Finish Work.
- Accessibility labels and values for the timer, rows, charts, and menu bar item; Reduce Motion support.
- App icon, About, and onboarding artwork from the existing logo.
- `CalendarTimeLoggerKit` Swift package with 83 Swift Testing tests.
- DEBUG-only demo mode for manual QA.
- Documentation system: README, architecture, product requirements, ADRs, development, testing, release, privacy, versioning, and documentation rules.

### Changed

- Replaced the Xcode template's "Hello, world" app with Calendar Time Logger.
- Restricted the target to macOS (removed iOS and visionOS platforms and settings).
- Product name set to "Calendar Time Logger"; Swift language mode 6; version 1.0.0 (1).
- Moved `Assets.xcassets` into `Resources/`.
- Removed the unused "User Selected Files (read-only)" sandbox entitlement.

### Known Limitations

- Totals and Work Log grouping count a session on the day it **started**; sessions that cross midnight are not split.
- "View in Calendar" opens the Calendar app but can't select the specific event (no public API).
- The optional work summary is part of the completion notification; there is no separately scheduled daily summary.
- Cancelled sessions are retained in the store but can't be viewed or permanently discarded from the UI.
- Editing a finished session doesn't change its individual pauses; pauses outside new start/finish times are trimmed.
- If Calendar sync is off when a synced session is edited, its existing event isn't updated.
- Changing a template's calendar doesn't move events that already exist.
- Reconciliation checks the 500 most recent finished sessions.
- Work Logs, Dashboard, and Analytics load all finished sessions into memory; very large histories may be slow.
- The main window and settings are in English only; no localizations are provided.
- No UI test target. Views, App Intents, launch at login, and writing events to a real calendar were not exercised by automated tests (see [TESTING.md](../Testing/TESTING.md)).
- The project is signed with a personal development team, so Developer ID signing and notarization are not configured (see [RELEASE.md](RELEASE.md)).
- Out of scope for V1: iCloud sync, iPhone, iPad, and Apple Watch.

[Unreleased]: CHANGELOG.md
[1.4.0]: CHANGELOG.md
[1.1.0]: CHANGELOG.md
[1.0.0]: CHANGELOG.md
