# Testing

## Strategy

- **Core logic is tested in the Swift package** with Swift Testing (`swift test`). The tests run in about a quarter of a second with no app host, no signing, and no permission dialogs.
- **System services are mocked behind protocols.** `MockCalendarProvider` implements `CalendarProviding` (EventKit) and `MockNotificationScheduler` implements `NotificationScheduling` (UserNotifications). Real permission prompts are never triggered by tests.
- **Persistence uses real SwiftData** with an in-memory container. Relaunch is simulated by building a new `SessionService` on the same container, or, in the migration and 30-day suites, by reopening an on-disk store in the temporary directory.
- **Time is controlled** through `TestClock`, which is injected into every service.
- **Symbols are checked against the installed SF Symbols.** Tests render every catalog symbol with `NSImage(systemSymbolName:)`, and `scripts/generate-symbol-catalog.py --check` validates names against the system catalog.
- **Exported workbooks are read back independently.** `XLSXReader` (test support) parses the ZIP central directory, verifies CRCs, inflates entries, and parses worksheets with `XMLParser`, so tests check real cell values, types, and styles.
- **UI iconography is audited by script.** `scripts/audit-ui-icons.py` checks every SF Symbol literal in the app and package sources against the SF Symbols installed with macOS and fails on emoji outside the 1.0 migration table and DEBUG demo seeding.
- **Documentation is audited by script.** `scripts/check-doc-links.sh` verifies the layout and every relative link; `scripts/audit-doc-emoji.py` fails if any Markdown file contains an emoji. Both run in `scripts/verify.sh --full`.
- **UI** is verified manually with DEBUG demo mode (see [DEVELOPMENT.md](../Development/DEVELOPMENT.md#demo-mode-debug-only)) and the checklist below. There is no UI test target in V1. Relaunch checks use `-demoPersistentStore`, which keeps demo data on disk without touching the real store.

## Running

```bash
cd CalendarTimeLoggerKit && swift test     # tests only
scripts/verify.sh                          # tests + app build
scripts/verify.sh --full                   # + analyzer, Release build, doc links
```

## Coverage

216 tests in 23 suites.

| Suite | File | Covers |
| --- | --- | --- |
| Session state machine | `SessionStateMachineTests.swift` | Valid lifecycle; finish/cancel from paused; terminal states reject all events; invalid transitions; exact transition table |
| Duration calculation | `SessionTimingTests.swift` | Documented 10:00–12:24 example (2h 24m wall, 25m paused, 1h 59m active); open sessions; clock skew; pause clipping; formatting |
| Session engine | `SessionServiceTests.swift` | Start (persisted, no Calendar); single active session; pause/resume; Finish Work with durations and event; finish while paused; cancel; invalid transitions; change template; notes; storage-unavailable guard; editing with event update; invalid edits; delete with event removal; pause on sleep |
| Persistence and recovery | `PersistenceRecoveryTests.swift` | Active session saved (verified through a separate context) and reloaded after relaunch; resume, finish, finish-at-last-heartbeat, and cancel after relaunch; template deletion keeps logs; default templates seeded once; settings persistence |
| Work templates | `TemplateTests.swift` | Create with defaults; edit (icon, background); delete; validation including unknown icons; rename to self; icon normalization to symbols; duplicate; default templates; ordering; menu bar config coding for every mode; 1.0 configuration migration; invalid stored colors; colors; tag parsing |
| Menu bar presentation | `MenuBarFormatterTests.swift` | All six display modes; separator; per-segment colors; background pill with automatic contrast; WCAG contrast rule; paused symbol; hidden templates; legacy and unknown icons never reach the menu bar; live template configuration |
| Menu bar lifecycle | `MenuBarLifecycleTests.swift` | CTL identity at launch; idle → working → paused → finished returns to CTL; cancel returns to CTL; recovered session after relaunch; Show CTL setting independent of sessions; single-instance policy (no duplicate CTL) |
| SF Symbol icons | `SymbolIconTests.swift` | Every catalog symbol renders; 18 categories, ≥ 250 unique symbols; search; fallback; 1.0 emoji mapping (variation selectors, skin tones); every mapping target valid; persistent migration of templates and sessions, once, without other changes; logs and new sessions carry symbols |
| Excel export | `WorkLogExportTests.swift` | Package structure; row values with the default 16 columns (dates, times, durations as serials, template, category, Urgent, Important, tags, notes, calendar, status, identifier); Summary totals by template, day, week; scopes (all, today, week, month, current filter; open and cancelled excluded); empty export; 5,000-session export; Save panel cancellation; successful write never changes work logs; permission, disk-full, and write failures; escaping and cell limits; invalid values; time zones; local-date file name; CRC-32 |
| Change template of a completed work log | `TemplateReassignmentTests.swift` | Identity, tags, timing, notes, and the owned event are updated without duplicates; unsynced sessions stay out of Calendar; guards |
| Settings | `SettingsTests.swift` | New settings' defaults and persistence; 1.0 default display mode keeps its look |
| Calendar integration | `CalendarServiceTests.swift` | Discovery; calendar resolution order; event creation and notes; notes/tags exclusion; update; permission denied; contextual permission request; write-only access; creation failure and retry; missing calendar; read-only calendar; sync disabled; ownership (unowned never modified, per-session ownership); identifier drift re-linking; reconciliation |
| Work Logs and analytics | `WorkLogAnalyticsTests.swift` | Durations and template association; date grouping; filters; search; today and weekly totals; daily totals; streak |
| Sidebar navigation | `AppSectionTests.swift` | All seven destinations in order (five work sections, Settings, About); row identity is `AppSection` (regression for unclickable sidebar); selecting each section from each section; `nil` selection keeps the current section; unique, real SF Symbols; stable raw values |
| Store migration | `StoreMigrationTests.swift` | A store written with the frozen 1.1 models opens under the current schema: templates and sessions read as Not Urgent / Not Important and category General, and keep every other value (icon, color, calendar, tags, notes, sort order, dates, menu bar configuration, notification behavior, times, pauses, sync status, event identifier); a migrated store then records new work with priority and reopens with it, keeping the 1.1 session unchanged; a store written with the frozen 1.2 models opens with every template and work log in General, keeping priority, notes, times, and event identifiers; after that migration a template still can't be saved without a category, and a new session keeps its category across a reopen while the 1.2 work log stays General; a store written with the frozen 1.3 models opens with a category list of the built-ins plus template categories (work log names don't become entries), changing no template or work log, and a delete after that migration sticks across a reopen without reseeding; opening a store the current schema wrote is a no-op. Confirmed to abort against plans whose V1 (1.2.0) or V2 (1.3.0) points at the current models, which is the failure this suite exists to catch |
| Task priority | `TaskPriorityTests.swift` | Template defaults (No / No); a template stored before 1.2 reads as No / No and keeps every other value; editing and duplicating carry priority; a session inherits the template's values; a session-level override is what the work log records; editing the template afterwards never changes recorded work; reassigning a template keeps the session's priority; values survive a relaunch; live changes during a session, with the final value logged; correcting a completed session; quick tasks (name, tags, notes, no template, validation, one-open-session rule); Work Logs priority filters; analytics totals for all four combinations, shares, overlapping urgent and important totals, summaries, per-template splits, and date-range scoping; Calendar notes carry the priority while the title stays the template name; quadrant model round-trips |
| Excel export columns | `ExportColumnTests.swift` | A five-column Priority Analysis export contains exactly those columns with correct Yes/No values, and no unselected value leaks into the sheet; user column order is the workbook's order; empty values export as empty cells; an empty selection is refused before the Save panel; selection editing (toggle, reorder, select/deselect all, duplicates) and round-tripping through settings, including unknown stored names; presets; the Summary sheet's Work by Task Priority block; the preview's headers, row count, and formatting |
| Categories | `CategoryTests.swift` | Name normalization, case-insensitive identity, canonical spelling (including built-ins before any template uses them), validation; built-ins-first ordering; default templates' categories; a template can't be created or saved without one; renaming changes templates only, merges onto an existing name, and never changes recorded sessions; a session inherits the template's category or takes one chosen at start; a template's later category change leaves earlier sessions alone; live changes; quick tasks (chosen and blank → General); editing a completed session; Change Template and reassignment move an inherited category and keep a chosen one; Calendar notes; Work Logs category filter, search, and category list; analytics with zero sessions, one session, several categories (totals, counts, shares summing to 1, templates and all four priority combinations per category), date-range scoping, sessions crossing midnight, and renamed categories; a real workbook with exactly Date, Template, Category, Duration, Urgent, Important in that order, values from recorded data, the Summary sheet's Work by Category block, and the Category Analysis preset |
| 30-day regression | `ThirtyDayRegressionTests.swift` | Thirty consecutive days of work driven through the real services against an isolated on-disk store and checked against an independent ledger: see [30-Day Regression](30-Day%20Regression.md). Also 20,000 logs across 7 categories aggregate in under 2 seconds |
| Edit and delete lifecycle | `EditDeleteLifecycleTests.swift` | `isLive` is false after a delete, both before and after it is saved (falsified: `!isDeleted` alone fails, and edits and Calendar syncs then reach a deleted work log); deleting a work log or template twice deletes it once without error, including models fetched after a relaunch; deleting with the event removes only that event; editing, moving, retrying, or removing the event of a deleted work log is refused and never calls Calendar; saving or duplicating a deleted template is refused; deleting the new work log while Calendar's permission prompt is up leaves Finish Work intact and writes no event (falsified by removing the guard in `finish`); deleting the template of a running session keeps the session and records its snapshot, category, priority, and time; template and work log edits and deletes survive reopening an on-disk store, and editing a template changes no recorded work |
| Category management | `CategoryManagementTests.swift` | The stored list seeds the built-ins once and reconciling is idempotent; creating tidies names, keeps unused categories, and refuses blanks, over-long names, and case-insensitive duplicates (a repeated Add can't create a twin); a created category survives reopening an on-disk store; **A** an unused category (including a built-in) is deleted, a repeat delete does nothing, and reconciling doesn't bring it back; **B** a category used by one template refuses a plain delete and moves the template when deleted with a destination; **C** migrating moves every template (same or missing destination refused), keeps the source until it is deleted, and General can't be deleted; **D** a category with only work logs is deleted while the work logs keep their name, priority, and times, Analytics still totals them under it, and the migrated template starts sessions in its new category; the open session keeps a deleted category through priority changes and finish; **E** renaming keeps the record's identity, renames every template, leaves work logs alone, and future sessions use the new name; renaming onto an existing name merges into it, and General can't be renamed; **F** after rename, migrate, and delete, reopening the store shows the same categories, templates, and work logs; templates never name an unlisted category; case-only duplicate records merge into the oldest |
| Calendar event boundaries | `CalendarBoundaryTests.swift` | The eight-case boundary matrix in both directions (10:00–11:00 / 11:00–12:00 adjacent; 10:59 start overlaps by 60 s; 10:00–12:00 / 11:00–12:00 overlap; 11:00–11:30 and 10:30 adjacency; 10:00:30–11:00:15 / 11:00:15 exact-second adjacency; 11:00:01 one-second gap; 11:01 end overlaps by 60 s) and 10:00–12:00 / 11:00–13:00; back-to-back sessions write exactly their recorded start and end to the provider and each log is exactly one hour; exact timing keeps seconds while nearest-minute timing rounds only the event; rounding never makes non-overlapping sessions overlap (exhaustive 5-second sweep) and keeps sub-30-second sessions exact; applying timing to existing events updates only owned events whose times differ, never foreign events, never work logs, and is idempotent; the setting defaults to exact and persists; picked minutes clear hidden seconds while untouched times keep them; editing a log to start where another ends is adjacent and writes adjacent events |
| Notifications | `NotificationServiceTests.swift` | Start notification gating; master switch; permission requested only when needed; denied permission; reminder schedule from active time; reminders cancelled on pause; completion with today's total; Calendar failure notification |

## What is not covered by automated tests

- SwiftUI views, the `MenuBarExtra` label rendering, and the Save panel (verified manually in demo mode; see the verification log).
- App Intents (compiled; not exercised through the Shortcuts app).
- The single-instance guard in the running app (the policy is unit tested). It wasn't exercised against a second non-demo copy, to avoid opening the real store from two processes.
- `EventKitCalendarProvider` and `UserNotificationScheduler` (thin adapters; they are compiled and exercised manually).
- Writing real events to Apple Calendar. During development the provider was exercised against the real Calendar database **read-only** (listing calendars, access status). No events were written to a real calendar. Verify this with the checklist before release.

## Manual QA checklist

Run it on a Release build before each release (see [RELEASE.md](../Releases/RELEASE.md)).

**Sessions**
- [ ] Start a template from the menu bar; the timer increments; no Calendar event exists yet.
- [ ] Start Work (⌥⌘S) shows the template's task priority; changing it affects only that session, not the template.
- [ ] Quick New Task (⌥⌘N) refuses to start without a name, and records the name and priority it was given.
- [ ] Change the priority during a session; the Work Log records the final values.
- [ ] The Start Work sheet shows the template's category; changing it affects only that session. A quick task records the category chosen for it.
- [ ] Change a template's category, then open an older Work Log: it still shows the category it was recorded with.
- [ ] Rename a category in Templates › Categories: the templates change, Work Logs don't.
- [ ] Categories › Add Category adds an unused category that stays after relaunch; a case-only duplicate is refused under the field.
- [ ] Categories › Move Templates… moves every template to the destination; the source stays with 0 templates.
- [ ] Delete an unused category (confirmation mentions its work logs); delete a used one (sheet requires a destination, then Move and Delete). Work Logs keep the old name; General offers no Rename or Delete.
- [ ] With a template editor open, rename its category in Categories: the editor's Category menu shows the new name without marking the template changed.
- [ ] New Template sheet in a small (900 x 560) window: nothing clipped at the sides, Task Priority visible under Basic Information, Cancel and Create Template always visible.
- [ ] Start Work: change Urgent or Important; the sheet says "Changed for this session only" and offers Use Template Defaults; the started session records the override and the template keeps its defaults.
- [ ] Settings › Calendar › Event Times: default Keep exact times; switching to Round to the nearest minute persists across relaunch.
- [ ] **Real Calendar (owner-approved run only):** finish sessions 10:00–11:00 and 11:00–12:00 (or edit two work logs to those times); open both events in Apple Calendar: start and end are exactly those times, and the events stack without a split at 11:00. Repeat with Round to the nearest minute and Update Existing Events…, then relaunch and check again.
- [ ] Analytics › Work by Category totals match the Work Logs list filtered to the same category and dates.
- [ ] Pause, wait, resume; the paused time appears on the Dashboard.
- [ ] Finish Work; the confirmation shows time range, duration, active work, and Calendar status.
- [ ] Quit with a session running, relaunch; **Active Session Detected** appears; each choice works.
- [ ] Sleep the Mac with "Pause the session when my Mac sleeps" on and off.

**Calendar**
- [ ] First Finish Work with access never requested shows the system prompt.
- [ ] The event appears in the expected calendar with the right times, title, and notes.
- [ ] Edit the log's finish time; the event updates. Delete with "Remove Calendar Event"; the event disappears and the app keeps running.
- [ ] Deny access in System Settings; finishing still saves the log and shows Sync Failed with a retry path.
- [ ] Delete an app event in Calendar; the log shows Event Missing.
- [ ] Click the event URL in Calendar; the app opens the work log.

**Edit and delete**
- [ ] Work Logs: Delete from the details pane, from a row's shortcut menu, and with the Delete key. Cancel deletes nothing; confirming removes the row, the pane shows No Selection, and the app keeps running.
- [ ] Work Logs: a row's **Edit Entry…** edits that row even when another is selected; Cancel and Esc change nothing; Save changes only that work log.
- [ ] Templates: Delete from the editor, a row's shortcut menu, and Edit › Delete. Deleting the running session's template says the session keeps running; finishing it still records the work log.
- [ ] Session › Cancel Session… asks first; Return keeps working.
- [ ] Quit and relaunch: edits and deletes are still there.

**Navigation**
- [ ] Click Dashboard, Templates, Work Logs, Calendar, and Analytics; each shows its screen and stays highlighted.
- [ ] The arrow keys in the sidebar and ⌘1–⌘5 move the highlight and the screen together.
- [ ] Hovering an unselected item shows a subtle highlight, in light and dark appearance.

**Task priority**
- [ ] A template created before upgrading shows Urgent No / Important No and keeps its name, icon, color, tags, calendar, notes, menu bar style, and notifications.
- [ ] Work Logs rows, the detail pane, and the filter menu all show and filter by priority.
- [ ] Analytics: the four combinations add up to the total for the selected range; urgent and important totals overlap as described.
- [ ] A Calendar event's notes contain the `Urgent: … · Important: …` line and the title is unchanged.

**Menu bar**
- [ ] The CTL Mark is legible on a light and a dark menu bar; each other CTL style still works.
- [ ] Quick New Task and Start with Priority appear inline in the popover without widening it.
- [ ] CTL appears at launch, stays while idle, shows the template during a session, returns to CTL after Finish Work and Cancel, and disappears on Quit.
- [ ] Launching a second copy activates the first; only one CTL item exists.
- [ ] Each display mode, with Auto and custom colors and with a background, in light and dark menu bars. Each CTL style.
- [ ] Hidden template shows the timer symbol; paused shows the pause symbol.

**Installer**
- [ ] `scripts/package-dmg.sh` completes and reports a version, size, and checksum.
- [ ] The DMG opens with the branded background, the app, and an Applications shortcut, and both labels are readable.
- [ ] Dragging the app onto Applications installs it; the installed app launches, shows the new icon, and shows one CTL item.

**Templates and icons**
- [ ] Icon picker: search, categories, selection; no emoji anywhere in the UI.
- [ ] The app icon fills the icon area in Finder, the Dock, and About (no gray plate).
- [ ] Upgrade a 1.0 store: templates and work logs show symbols.
- [ ] Calendar Event Appearance shows the resolved calendar's color.

**Export**
- [ ] Export each scope; Cancel in the Save panel writes nothing; the workbook opens in Excel and Numbers with correct values.
- [ ] Saving into a read-only location shows an error and keeps the sheet open.

**Accessibility**
- [ ] VoiceOver reads the menu bar item, timer (with value), Work Log rows, and chart marks.
- [ ] Every action is reachable by keyboard (Session menu shortcuts, ⌘1–⌘5, Tab through forms).
- [ ] Reduce Motion disables the numeric timer transition.
- [ ] Increase Contrast and both appearances remain legible.

**Documentation**
- [ ] `scripts/check-doc-links.sh` and `scripts/audit-doc-emoji.py` pass.
- [ ] Every screenshot matches the build being released, and none shows a real calendar name, file path, or other personal data.
- [ ] The [User Guide](../User%20Guide/README.md) page for each changed screen still describes it correctly.

**Other**
- [ ] Notifications: start, reminder, completion, Calendar failure, each respecting its settings.
- [ ] Shortcuts: Start Work, Pause or Resume Work, Finish Work.
- [ ] Open at login toggles correctly.

## Verification log (1.4.0 release documentation and DMG, 2026-09-17)

| Check | Result |
| --- | --- |
| `scripts/verify.sh --full` | 216 tests in 23 suites, Debug build, SF Symbols catalog check, UI icon audit (64 symbols, no emoji), `xcodebuild analyze`, Release build, 443 relative documentation links, and the Markdown emoji audit (59 files) all passed, with no compiler warnings |
| Anchors and website | All 30 `#anchor` links across README and Documentation resolve to headings; `https://abirbarman.com` redirects to `https://www.abirbarman.com/` and returns 200 |
| About | Demo build, main window About section: logo, "Version 1.4.0 (6)", **Developed by Abir Barman**, the abirbarman.com link, and "© 2026 Abir Barman" |
| Screenshots | 15 images recaptured from the 1.4.0 DEBUG demo build with `screencapture -l` window captures (no shadow), matching the framing of `03`, `04`, and `08`; the popover images come from `-demoMenuWindow` with the title bar cropped. `menu-bar-task-priority.png` and `menu-bar-quick-task.png` were **not** recaptured: synthetic clicks only highlighted the row in the preview window. CleanShot X was not used this round |
| DMG | `dist/Calendar-Time-Logger-v1.4.0.dmg` (2.8 MB, 1.4.0 build 6, Release): SHA-256 matches, `hdiutil verify` passed. Mounted read-only it contains only the app, the `Applications` symlink to `/Applications`, and the hidden `.background`, `.VolumeIcon.icns`, and `.DS_Store`. The app's `Info.plist` has the expected version, build, bundle identifier, minimum system 27.0, and `AppIcon`; `AppIcon.icns` is identical to the source; the signature verifies; `demoState` count is 0; no dSYMs or Swift modules. The Finder window shows the dark branded background, the app, the arrow, and Applications with readable labels |
| Signing | Apple Development certificate, `get-task-allow` present, entitlements as expected. `spctl` rejects it (not Developer ID); no notarization ticket |
| Installation | The app was copied out of the mounted DMG into a scratch folder: byte-identical and the signature still verifies. It was **not** installed into /Applications or launched, and the Release build was not run, because it would migrate the owner's real 1.3 store to schema version 4; the owner chose to install it themselves |

## Verification log (UI refinement, category management, and Calendar boundaries, 2026-09-17)

| Check | Result |
| --- | --- |
| `scripts/verify.sh --full` | Tests (216 in 23 suites), Debug build, SF Symbols catalog (367 entries, all valid), UI icon audit (64 literal symbols valid, no emoji), `xcodebuild analyze`, and Release build passed. Documentation links (446) and the Markdown emoji audit (59 files) passed after the documentation edits. Symbol constants not caught by the audit's literal patterns (`folder.badge.plus`, `folder.badge.minus`, `arrow.right.circle`, `ellipsis.circle`, `exclamationmark.circle.fill`, `star.fill`, `clock.arrow.circlepath`, `arrow.forward`) were checked against the installed catalog separately |
| Falsification | Disabling the built-in seeding in `reconcileCategories` failed the category management, migration, and category suites; restored, all pass |
| Clipped template sheet (root cause) | `TemplateEditorSheet` forced an 860 x 760 frame. A macOS sheet can't be larger than its window, so in a smaller window the content was wider than the sheet and was clipped on both sides, and the scroll area shrank. Replaced with a flexible frame; verified at a 900 x 560 window |
| Real Calendar | **Not tested.** No run wrote to the owner's calendars, and the shell can't read the Calendar database (macOS privacy protection), so the owner's existing event times weren't inspected. Event start and end values were verified at the provider boundary with the mock provider. Listed in the manual checklist as an owner-approved step |

Demo-mode regression matrix (DEBUG build, `-demo`, sample calendars, Calendar sync off; the installed app was not touched). Actions were driven with real mouse events and Accessibility, and each result was read back from the app's Accessibility tree or a window capture, not assumed from a button responding.

| Area | Action | Expected | Result |
| --- | --- | --- | --- |
| Templates | New Template sheet, 900 x 560 window, dark | Nothing clipped; Task Priority visible; footer visible | Passed |
| Templates | Create with a new category typed in place, Urgent Yes, **Create Template** clicked twice rapidly | One template, in the new category, Urgent | Passed: one "Client Onboarding" in "Client Work" with Urgent |
| Templates | Create with an empty name | Footer error, nothing created | Passed: "Give the template a name." |
| Templates | Editor at 900 x 560 | No horizontal clipping; header actions wrap; Save Changes disabled until a change | Passed (after fixes below); Save Changes read as disabled |
| Icon picker | Open, search "terminal", Return | Opens at the selected icon; all 10 columns and 18 categories visible; Return picks first match and closes | Passed |
| Categories | Add "work", **Add** pressed twice | One category | Passed |
| Categories | Rename "work" to "Professional Work" | Name updates in place, message shown | Passed |
| Categories | Move Templates from Design to Professional Work, pressed twice | Template moves once; Design keeps its 6 work logs | Passed |
| Categories | Delete unused Design (confirmation), confirm pressed twice | Confirmation names the 6 work logs; deleted once | Passed |
| Categories | Delete Content (used by Writing) with Move and Delete to General | Writing moves to General; Content removed | Passed |
| Categories | Work Logs after the changes | Old Writing logs still say Content | Passed |
| Categories | Add "Operations" with `-demoPersistentStore`, relaunch | Still listed | Passed |
| Priority | Start Work: Research (defaults Urgent No, Important Yes) changed to Urgent Yes, Important No; **Start Session** pressed twice | One session with the override; sheet says changed for this session; template unchanged | Passed |
| Menu bar | `-demoMenuWindow` during that session | Worded Urgent badge under the name | Passed |
| Menu bar | Pause, Resume, Finish Work (Finish pressed twice) | Priority preserved; one completion showing Urgent Yes, Important No | Passed |
| Work Logs | Rows at 900 x 560 with the inspector open, light | Name, priority, duration visible | Passed after the compact row fix |
| Work Logs | Edit Entry: change Finished to overlap other logs, then Cancel | Overlap warning names the logs; nothing saved | Passed |
| Settings | Calendar › Event Times to Round to the nearest minute, relaunch | Persists | Passed; Update Existing Events… disabled with sync off, as designed |
| Appearance | Light and dark | Readable selection, badges, and rows | Checked in both: template sheet, editor, Categories, delete sheets, Start Work, and menu window in dark; Work Logs, Edit Entry, and Settings in light |
| Analytics, Excel export | Priority and category output | Unchanged by this work | Not re-run manually; covered by the existing automated suites, which pass |

Fixes from that pass: the template editor header squeezed the name and the fixed icon and color rows pushed cards past a narrow pane (now adaptive and wrapping); Work Logs rows lost the template name and cut durations in a narrow list (now a two-line compact row); the Important star disappeared on a selected row (priority symbols and chips use white on the selection); the Categories list painted an empty striped row.

## Verification log (Edit and Delete regression audit, 2026-09-17)

| Check | Result |
| --- | --- |
| Method | The DEBUG build driven through the Accessibility API with real mouse and keyboard events (a scratch `swiftc` helper), window-only captures, stderr captured, and crash reports checked. Demo mode throughout: the real store and real calendars were never opened. The live CTL popover couldn't be opened by synthetic input (collapsed behind the crowded menu bar), so menu bar content was driven in the `-demoMenuWindow` preview, which hosts the same view |
| Crash found | Work Logs › Delete › Delete and Remove Calendar Event terminated the app: `SwiftData/BackingData.swift:293: Fatal error: This backing data was detached from a context without resolving attribute faults … \WorkSession.tags`. Backtrace: `WorkLogDetailView.body` → `WorkLog.init(session:)` → `WorkSession.tags.getter`, during the alert's close. Reproduced before the fix; after it, the same path and every neighbor below ran without a crash |
| Other failures found | Session › Cancel Session discarded the session without confirmation; the menu bar start form had no way out after its template was deleted; a long template name widened the editor's Menu Bar Preview over the Name field; inspector tags broke mid-word; no row-level Edit or Delete in Work Logs or Templates, and no Delete key |
| Work Logs after the fix | Details pane Delete: Cancel, Esc, and both confirm choices; row shortcut menu Delete on an unselected row: Cancel, then confirm; Delete key: confirmation, Esc; delete while searching, then select another row; ⌘E and Edit Entry: Cancel, Esc, Save one field, Save several fields; row shortcut menu Edit Entry edits the clicked row, not the selection, and Save changes only that row |
| Templates after the fix | Create with an empty, duplicate, 61-character, and valid Unicode name; Save (⌘S); Revert; editor Delete: Cancel and confirm; row shortcut menu Edit Template and Delete: Cancel; Edit › Delete; deleting the running session's template (the session continued and finished into a work log); deleting a template while its menu bar start form was open. The physical Delete key does not reach the Templates list: a sidebar-style list doesn't take keyboard focus on click, which is standard for source lists; Edit › Delete works |
| Sessions and menu bar | Start Work sheet with a priority override; Pause/Resume/Finish from the Dashboard, the preview, and ⌥⌘P/⌥⌘F; rapid Pause/Resume; double-click Finish Work and Quick New Task Start Work (one session, no error); Change Category and Priority: Cancel and Save; Change Template menu; Add Note; Cancel Session from the Dashboard and the preview (Keep Working, Esc, confirm; Return doesn't discard) and from the Session menu; Quick New Task from the Session menu and the preview (blank name refused); Today's Work, Work Logs, and Edit Template… rows; the Start Template submenu is disabled during a session |
| Other screens | Analytics: all five ranges, with Last 30 Days matching the Work Logs count and total; Export: Deselect All (refused with an explanation), Select All, a single column, Preview, the Save panel opened and cancelled (no file written; the sheet stayed open); Settings: every pane's controls listed, three settings changed, persisted across a relaunch, changed back, and persisted again; Calendar section rendered with sample calendars |
| Restart persistence | With `-demoPersistentStore`, across seven relaunches: template create, rename, tags, notes, priority, and delete; work log tag edit and delete; a new session's priority change; settings |
| Final smoke sequence | Create, edit and save, edit and revert, delete and cancel, delete a template; create one, start, pause, resume, finish; edit a work log and cancel, edit and save, delete and cancel, delete; change the Analytics range; relaunch; menu bar quick task, pause, resume, finish; Work Logs; export to the Save panel and cancel; quit with ⌘Q; relaunch: every change present, deleted items absent, no crash report after the fix |
| `scripts/verify.sh --full` | Tests (193 in 21 suites), Debug build, SF Symbols catalog (367 entries, all valid), UI icon audit (64 symbols, no emoji), `xcodebuild analyze`, Release build, 427 documentation links, and the Markdown emoji audit (57 files) passed with no warnings. A clean Debug and Release build followed; the Release app's signature verifies and it contains no demo code |
| Not done | The Release build was not launched and no real Calendar event was written: both would use the owner's real store and calendars, and the installed app was running. No XCUITest target exists, so no UI tests were added |

## Verification log (1.3.0 branding and documentation)

| Check | Result |
| --- | --- |
| `scripts/verify.sh --full` | Tests (184 in 20 suites), Debug build, SF Symbols catalog (367 entries, all valid), UI icon audit (64 symbols, no emoji), `xcodebuild analyze`, Release build, 427 documentation links, and the Markdown emoji audit (57 files) all passed; the link and emoji checks were rerun after the last documentation edits and passed |
| App icon | Regenerated from the original `logo.png` glyphs. Rendered through `NSWorkspace.icon(forFile:)` for an app copied out of the DMG: masked into the system squircle with no plate, and "CTL" legible at 16, 32, 64, 128, and 256 pt on light and dark backgrounds |
| CTL mark | Settings › Menu Bar preview in the demo build shows the original wordmark on the black plate, legible on light and dark strips. The live menu bar item could not be captured: the menu bar was crowded, and macOS collapsed the item behind its overflow control |
| Welcome screen | Demo build (`-demoState onboarding`) in dark and light appearance: black header with the centered wordmark and product name in both |
| Screenshots | 26 images recaptured with CleanShot X window capture after the branding changes (full-window captures of the demo build, plus crops of those captures and captures of the real menu bar popovers and the icon picker). All 27 images referenced by README and Documentation exist, open, and date from that capture run; none is unreferenced. The menu bar mark images are crops of in-app previews, not of the live menu bar |
| DMG | `dist/Calendar-Time-Logger-v1.3.0.dmg` (2.6 MB, 1.3.0 build 5, Release): SHA-256 matches, `hdiutil verify` passed, mounted read-only it contains the app (icon identical to the generated `AppIcon.icns`, valid signature, no demo code, no dSYMs), the Applications symlink, the dark background, the layout, and the volume icon. Opened in Finder on a Retina display, both labels sit centered on their plates |
| Installation | The app was copied out of the mounted DMG and its signature verified. It was **not** installed into /Applications or launched, and the Release build was not run: both would open and migrate the owner's real 1.2 store, and the owner chose to install it themselves |
| CleanShot X | Window capture (⌥⌘⌃W) worked throughout. A `cleanshot://` URL command triggered CleanShot's permission prompt, which the owner allowed; area captures through it returned the wrong region for the menu bar and weren't used |

## Verification log (1.3.0 development)

| Check | Result |
| --- | --- |
| `swift test` | 184 tests in 20 suites passed |
| `scripts/verify.sh --full` | Tests (184 in 20 suites), Debug build, SF Symbols catalog check (367 entries, 18 categories, all valid), UI icon audit (64 symbols valid, no emoji), `xcodebuild analyze`, Release build, 383 documentation links, and the Markdown emoji audit (56 files) all passed |
| Migration | A store written with the frozen 1.2 models opened under schema V3 with every template and work log in General and every other value kept (`StoreMigrationTests`). Pointing `CalendarTimeLoggerSchemaV2` at the current models made that suite abort with the same uncaught `NSException` that crashed the first 1.2.0 install; the frozen models pass |
| History preservation | With `renameCategory` altered to also rewrite sessions, both `CategoryTests` and the 30-day regression failed; restored, both pass |
| 30-day regression | Passed: 63 completed and 1 cancelled session over 30 consecutive days, two relaunches, analytics, filters, and export all matching an independent ledger. See [30-Day Regression](30-Day%20Regression.md) |
| Real workbook | A workbook generated by the package from five recorded sessions was written to disk and inspected independently (ZIP integrity and worksheet XML with Python, rendered with Quick Look). The Work Logs sheet contained exactly Date, Template, Category, Duration, Urgent, Important in that order, with the recorded dates as serials, durations as day fractions (90 minutes = 0.0625), each template's category, and the per-session Yes/No values; the Summary sheet's Work by Category block totalled each category |
| Demo-mode UI pass | Dashboard idle and active, Templates with Manage Categories, the template editor, Start Work, Quick New Task, Change Category and Priority, Work Logs list and inspector (synced and Sync Failed), Calendar, Analytics (This Week, and Last 30 Days with the category breakdown expanded), Work Completed, the export sheet, and the real menu bar popover idle, active, with the inline quick task form, and with the inline category and priority editor |
| Fixes from that pass | Demo sessions were all in General; the demo read the real calendar list (now sample calendars); the demo's seeded sync failure showed a Calendar warning on every launch (now `-demoSyncFailure`); the Category menu didn't line up with the priority controls in the change sheet and the popover forms |
| Screenshots | Captured with CleanShot X window capture (⌥⌘⌃W) from the DEBUG demo build, dark appearance, 1440×900 window: `01-dashboard.png` … `14-excel-export.png`, plus `start-work.png`, `work-log-sync-failed.png`, `menu-bar-quick-task.png`, and `menu-bar-task-priority.png` (the last three are crops or popover captures). Each was reviewed; none contains a real calendar name or other personal data. The active menu bar item sits under the MacBook notch, so the active popovers were opened from the external display's menu bar and are 1x |
| DMG | `scripts/package-dmg.sh` produced `dist/Calendar-Time-Logger-v1.3.0.dmg` (2.5 MB, 1.3.0 build 5, Release). SHA-256 matched, `hdiutil verify` passed; mounted read-only it contained the app, an Applications symlink to `/Applications`, the background, the Finder layout, and the volume icon; the app carried `AppIcon.icns`, `LSMinimumSystemVersion` 27.0, a valid signature, no DEBUG demo code, and no dSYMs. Opened in Finder, the window showed the branded background, the app, the arrow, and Applications |
| DMG signing | Development-signed (Apple Development); Gatekeeper (`spctl`) rejects it and it is not notarized. No Developer ID identity is installed on this Mac |
| Not done | The DMG's app was **not launched**: it shares the installed app's bundle identifier and sandbox container, so launching it would migrate the real 1.2 store. Installing over the real 1.2.0 install is a manual step for the owner |

## Verification log (1.2.0 development)

| Check | Result |
| --- | --- |
| `swift test` | 159 tests in 18 suites passed |
| `scripts/verify.sh --full` | Tests (159 in 18 suites), Debug build, SF Symbols catalog check (367 entries, 18 categories, all valid), UI icon audit (64 symbols valid, no emoji), `xcodebuild analyze`, Release build, 337 documentation links, and the Markdown emoji audit (52 files) all passed |
| Migration | A store written by the 1.1 models opened under schema V2: templates and sessions gained `isUrgent`/`isImportant` as `false` and kept every other value (covered by `TaskPriorityTests`) |
| Real workbook | Exports generated by the package and inspected independently (ZIP + XML, and Quick Look). A five-column **Priority Analysis** export contained exactly Date, Template, Active Duration, Urgent, Important, with correct serials, durations, and Yes/No values, and no unselected value anywhere in the sheet. The default 15-column export contained the same data plus tags, notes, calendar, event status and identifier, and session status, with empty notes written as empty cells |
| Demo-mode UI pass | Dashboard (idle and active), Start Work sheet, Quick New Task (typed, priority changed, started), Change Task Priority, Work Completed, Work Logs list and detail, Analytics in Today and This Week with the By Template breakdown, the export sheet's Columns and Preview tabs with the Priority Analysis preset, the Templates editor, Settings › Menu Bar, and the menu bar popover idle, with the inline quick task form, during a session, and with the inline priority editor |
| Fixes from that pass | The export sheet clipped its Summary row (form height); an unused priority combination read "< 1m" instead of 0m; the compact priority labels wrapped in the menu bar popover; the running session's priority chips truncated in the popover header and are now symbols; Yes/No wrapped in the Work Logs inspector |
| Real install | Installing 1.2.0 over 1.1.0 and launching it **crashed on first launch**: the migration plan's V1 pointed at the current models, so the 1.1 store matched no version and Core Data raised an Objective-C exception inside `migrateStoreWithContext:` (`SIGABRT`, no Swift error to catch). The store was not damaged — 1.1.0 reopened it with all data. Fixed by freezing the 1.1 models in `CalendarTimeLoggerSchemaV1`, and covered by `StoreMigrationTests` |

## Verification log (documentation, unreleased)

| Check | Result |
| --- | --- |
| `swift test` | 131 tests in 15 suites passed |
| `scripts/verify.sh --full` | Tests, Debug build, SF Symbols catalog check (367 entries, 18 categories, all valid), UI icon audit (62 symbols valid, no emoji), `xcodebuild analyze`, Release build, 294 documentation links, and the Markdown emoji audit (49 files) all passed |
| Icon picker size | The running app's picker reports **314 icons**, matching `SymbolCatalog.allNames`. The catalog's 367 entries include symbols listed in more than one category. README, ARCHITECTURE, PRODUCT_REQUIREMENTS, and the 1.1.0 changelog entry were corrected from 367 to 314 |
| Screenshots | Captured from the DEBUG demo build (`-demo -demoAppearance dark -demoWindowSize 1440x900`) with `screencapture -l <window id>`, restricted to windows owned by the demo process so the installed app's windows and real data were never captured. Each was reviewed before committing |
| Screenshot privacy | The Calendar screen and the template editor's Recording and Calendar Event Appearance cards show the *real* calendar list, because the demo build inherits the installed app's Calendar permission. Those captures were cropped to regions containing no calendar names |
| Documentation images | All 46 image references across README and `Documentation/` resolve, open with `sips`, are under 260 KB, and carry descriptive alt text |
| User Guide navigation | Every page's Back / Previous / Next chain matches the order in `Documentation/User Guide/README.md`, `Documentation/README.md`, and the root README |
| Link checker regression | `scripts/check-doc-links.sh` treated `%20` literally and reported percent-encoded paths as broken; it now decodes them. Verified against the new `User Guide/` paths |

## Verification log (1.1.0 development)

| Check | Result |
| --- | --- |
| App icon | Rendered through `NSWorkspace.icon(forFile:)` for the built and installed app: the flat black mark fills the tile, masked into the system squircle, with no gray compatibility plate. Measured all three deliveries first — a grid-shaped asset-catalog icon and a full-bleed asset-catalog icon are both plated; only the `.icns` is not ([ADR-024](../Decisions/ADR-024-flat-icns-app-icon.md)) |
| Menu bar redesign | Popover captured from the running app at 288 pt: header hierarchy, template rows with chevron menus, utility rows, right-aligned shortcuts, and footer all legible; CTL mark captured in the real menu bar |
| Menu bar actions (demo mode, Accessibility API) | Start, Pause, Resume, Finish Work, Change Template (menu selection), Add Note, Cancel Session (with confirmation), Today's Work, Work Logs, Open Calendar Time Logger, Settings, Edit Template…, Quit; closing the main window keeps the app and CTL running |
| DMG | `scripts/package-dmg.sh` produced `Calendar-Time-Logger-v1.1.0.dmg` (2.7 MB, build 3); `hdiutil verify` passed; the mounted image contained the app, the Applications symlink, background, and layout; the app was installed from the image, launched, and reported 1.1.0 (3) with one CTL item |
| Documentation | Moved into `Documentation/`; `scripts/check-doc-links.sh` reports a valid layout and resolving links, and a negative test (stray root file plus a broken link) fails as expected |
| UI icon audit | `scripts/audit-ui-icons.py`: 60 SF Symbol names valid on macOS 27.0, no emoji in UI sources |
| Baseline before changes | `swift test`: 89 tests in 10 suites passed; Debug build succeeded |
| `swift test` | 131 tests in 15 suites passed |
| `scripts/verify.sh --full` | Tests, Debug build, SF Symbols catalog check (367 entries, 18 categories, all valid), `xcodebuild analyze`, Release build, and 103 documentation links all passed |
| Clean Release build | Succeeded with no warnings; `demoState` absent from the binary; version 1.1.0 (2) |
| Entitlements (built app) | `app-sandbox`, `personal-information.calendars`, `files.user-selected.read-write` (plus `get-task-allow` from development signing) |
| 1.0 store compatibility | A store written by the 1.0.0 package opened with the 1.1.0 models, schema, and migration plan; data intact; 1.0 menu bar configurations mapped; icons converted, saved, and reopened |
| CTL lifecycle (demo mode, Accessibility API) | Exactly one status item at launch labeled “not working”; after Start: “working on Software Engineering”; Pause: “paused on …”; Resume; Finish Work: back to “not working”; no extra sessions during idle waits; Quit (popover row and main menu) ended the process and removed the item; relaunch showed one item |
| Menu bar rendering | Captured in the real menu bar: CTL badge (template image), blue pill with laptop symbol and ticking duration, paused symbol |
| Excel | A workbook recorded through `SessionService` and written by `WorkLogExportService` opened in Microsoft Excel with no repair prompt; values, date/time and `[h]:mm:ss` formats, filter, and Summary totals were read back through Excel's AppleScript and were correct. A workbook saved by the app through the real Save panel passed ZIP CRC and content checks. A file-name date bug (UTC instead of local date) was found and fixed |
| Visual check (demo mode, dark and light) | Dashboard (idle, active), Templates with symbol picker, Work Logs with inspector, completion sheet, menu bar popover (idle, active, completion), export sheet and Save panel, Settings, About, legacy-icon migration |
| Emoji audit | No emoji in app or package sources outside the 1.0 migration table and DEBUG demo seeding of legacy data |

## Verification log (1.0.0 development)

| Check | Result |
| --- | --- |
| `swift test` | 89 tests in 10 suites passed |
| Debug build | Succeeded, no warnings |
| Release build | Succeeded, no warnings; demo code absent from binary |
| `xcodebuild analyze` | Succeeded, no issues |
| Entitlements (built app) | `app-sandbox`, `personal-information.calendars` only (plus `get-task-allow` from development signing) |
| `calendartimelogger://session/<id>` URL | Opened by LaunchServices into the running instance, which switched to Work Logs (registered Debug build, demo mode) |
| Documentation links | `scripts/check-doc-links.sh`: 84 relative links resolve; negative test confirmed broken links fail |
| Sidebar navigation (after fix) | Real mouse clicks posted to each row of the Debug demo build: every item moved the outline selection (`AXSelectedRows`) and the destination (window title) to the clicked section. The same clicks on the unfixed build (and on the installed 1.0.0 app) changed nothing and reported no selected rows. Arrow keys and ⌘1/⌘5 verified. Selected and hover states checked in dark and light appearance |
| Visual check (demo mode) | Onboarding, Dashboard (active, recovery), completion sheet, Work Logs, Templates, Calendar, Analytics, menu bar popover, all menu bar label modes in light and dark |
