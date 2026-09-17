# Product Requirements — Calendar Time Logger V1 (1.1.0)

Status key: **Implemented** (in code and tested or manually verified), **Partial** (see note), **Out of scope** (V1 deliberately excludes it).

## 1. Product philosophy

Calendar Time Logger records real work sessions live. **The user's actual work is the source of truth; Apple Calendar is the output.** Calendar events come from finished live sessions, never from planned schedules.

## 2. Non-negotiable product rules

| # | Rule | Status | Where enforced |
| --- | --- | --- | --- |
| 1 | Starting a template does not create a Calendar event | Implemented | `SessionService.start`; test `startSession` |
| 2 | Finishing a live session creates the Calendar event | Implemented | `SessionService.finish` → `CalendarService.sync`; test `finishWork` |
| 3 | `WorkSession` is the source of truth | Implemented | [ADR-004](../Decisions/ADR-004-worksession-source-of-truth.md) |
| 4 | Calendar failure never destroys the work log | Implemented | Save before sync; tests `permissionFailure`, `creationFailure` |
| 5 | Only app-owned events are updated | Implemented | Ownership URL; tests `eventOwnership`, `ownershipIsPerSession` |
| 6 | Template customization controls menu bar presentation | Implemented | `MenuBarService`; test `serviceUsesTemplateConfiguration` |
| 7 | One active session at a time | Implemented | [ADR-007](../Decisions/ADR-007-one-active-session.md); test `singleActiveSession` |
| 8 | V1 is macOS only | Implemented | `SUPPORTED_PLATFORMS = macosx` |
| 9 | No iCloud, iPhone, iPad, or Watch in V1 | Implemented | `cloudKitDatabase: .none`; no other targets |
| 10 | Documentation stays synchronized with implementation | Process | [DOCUMENTATION_RULES.md](../Development/DOCUMENTATION_RULES.md) |

## 3. V1 requirements

### Work Templates

| Requirement | Status |
| --- | --- |
| Name, icon, color, default calendar, tags, notes | Implemented |
| Default task priority (Urgent, Important), mandatory and always set | Implemented (defaults to No / No, including for templates created before 1.2) |
| Category, mandatory and always set; choose, create, and rename categories | Implemented (six built-ins plus names in use; ≤ 40 characters; case-insensitive; rename applies to templates only; templates created before 1.3 are General) |
| Icons are SF Symbols from a broad, searchable, categorized picker; no emoji in the UI | Implemented (314 distinct validated symbols across 367 catalog entries, 18 categories) |
| Existing emoji icons migrated to SF Symbols without data loss | Implemented (once at launch; verified against a 1.0 store) |
| Duplicate a template | Implemented |
| Default notification behavior (start, finish, reminder interval) | Implemented |
| Menu bar configuration per template | Implemented |
| Creation and modification dates | Implemented |
| Create, edit, delete, reorder; validation (non-empty, ≤ 60 characters, unique, icon required) | Implemented |
| Default templates on first launch | Implemented (seeded once) |

### Live sessions

| Requirement | Status |
| --- | --- |
| Records session ID, template ID, start, state, pause and resume timestamps, paused/active duration, finish, notes, tags, calendar ID, event ID | Implemented (durations derived, not stored) |
| Timestamp-based timer; UI refreshes every second | Implemented |
| Explicit state machine with invalid transitions rejected | Implemented |
| Start persists immediately and applies the template's menu bar and notification settings | Implemented |
| Pause / Resume with accurate intervals | Implemented |
| Finish Work: capture time, validate, persist, create log, sync Calendar, update menu bar, confirm | Implemented |
| Cancel | Implemented (cancelled records kept, hidden from logs) |
| Wall-clock and active duration both kept | Implemented |
| Task priority captured per session, defaulting from the template and overridable before the session starts | Implemented |
| Category captured per session, defaulting from the template, overridable when starting and while running, never changed by later template edits | Implemented (quick tasks choose one, General by default) |
| Change the task priority of a running session; the work log records the final values | Implemented |
| Quick New Task: named work with a priority and no template | Implemented |
| Change template of the running session | Implemented |
| Change template of a completed work log (updates its Calendar event) | Implemented |
| Add note to the running session | Implemented |

### Apple Calendar

| Requirement | Status |
| --- | --- |
| Permission handling, with no unnecessary requests | Implemented |
| Multiple calendars; read available calendars | Implemented |
| Global default calendar and per-template override | Implemented |
| Per-session calendar override | Implemented in Work Log details for finished sessions (the service also supports it for an open session, but there is no UI for that in V1) |
| Create events after finished work | Implemented |
| Update app-created events after edits | Implemented |
| Remove app-created events when deleting a log (optional) | Implemented |
| Reconcile deleted or re-identified events | Implemented |
| Event notes with template, active and paused time, tags, notes | Implemented (internal session ID kept in the event URL, not the notes) |
| Usage description | Implemented |
| Per-template Calendar event color | **Not possible with EventKit** (events take their calendar's color). The template editor shows the resolved calendar color and explains the choice of calendar ([ADR-017](../Decisions/ADR-017-calendar-event-color-limitation.md)) |

### Work Logs

| Requirement | Status |
| --- | --- |
| Date grouping, search, template, category, tag, task-priority, and Calendar-status filters, date range | Implemented |
| Duration, notes, tags, category, task priority, session details, Calendar status | Implemented |
| Edit times, notes, tags, category, task priority, calendar; retry sync; delete | Implemented |
| List with detail inspector; actions Edit Entry, View in Calendar, Change Template, Delete | Implemented (Duplicate and Add to Shortcuts from the design reference are not offered: duplicating recorded work would invent sessions) |

### Excel export

| Requirement | Status |
| --- | --- |
| Export Work Logs to `.xlsx` through the Save panel (File menu, Work Logs, Dashboard, Settings) | Implemented |
| Work Logs sheet with date, start, end, duration, active, paused, template, category, Urgent, Important, tags, notes, calendar, event status, event identifier, session status | Implemented (dates and durations as Excel values) |
| User-selectable columns, in a user-chosen order, with presets and a preview | Implemented (17 columns; selection remembered; an empty selection is refused) |
| Summary sheet: totals, by template, by category, by task priority, daily, weekly | Implemented (optional) |
| Scopes: all, current filter, today, this week, this month | Implemented |
| Cancellation, permission, disk-full, and write errors handled; work logs never modified | Implemented |

### Analytics

| Requirement | Status |
| --- | --- |
| One date range for the whole screen: today, this week, last 7 days, this month, last 30 days | Implemented |
| Total work, sessions, average session length, streak, daily goal | Implemented |
| Task priority: all four combinations with time, share, and session count; overlapping urgent and important totals; per-template split | Implemented (Swift Charts; empty ranges show zeros, not a misleading share) |
| Work by category: time, sessions, and share per category for the selected range, with templates and priority combinations per category | Implemented (Swift Charts; grouped by the category recorded on each session; empty ranges show a native empty state) |
| Work by template (Swift Charts) | Implemented |
| Daily totals across the selected range | Implemented (hidden for Today, which has no trend) |

### Dashboard

| Requirement | Status |
| --- | --- |
| Greeting, current session with timer, start time, Pause, Finish Work, note field, Change Template, Cancel Session | Implemented |
| Ready to work, Start Work (default template plus menu), recent templates | Implemented |
| Today's Progress (per-template ring, daily goal) and Quick Actions | Implemented |
| Today's Work session by session, with total | Implemented |

### Menu bar

| Requirement | Status |
| --- | --- |
| Native `MenuBarExtra` | Implemented |
| Permanent CTL item while the app runs; reflects the active template; returns to CTL; removed on quit; never duplicated | Implemented (verified with the Accessibility API; single-instance policy unit tested) |
| CTL style: badge, text, or clock symbol | Implemented |
| Modes: Icon Only, Name Only, Duration Only, Icon + Duration, Name + Duration, Icon + Name + Duration | Implemented |
| Icon, name, and duration colors; background color (pill); separator; visibility | Implemented |
| Start Work, Pause, Resume, Finish Work, template selection, Add Note, Work Logs, Settings, open app | Implemented |

### Notifications

| Requirement | Status |
| --- | --- |
| Session started, optional reminder, completion, Calendar failure | Implemented |
| Optional work summary | Implemented as "today's total" in the completion notification (no separately scheduled summary) |
| Respect user settings; no spam | Implemented |

### Settings

General (launch at login, main window at launch, default template, daily goal, pause on sleep), Menu Bar (Show CTL, CTL style, seconds, display for new templates), Notifications, Appearance, Export (scope, Summary sheet, show in Finder), Calendar (access, defaults, event appearance), Privacy, About: **Implemented**, in the Settings window and the sidebar.

### Appearance and accessibility

| Requirement | Status |
| --- | --- |
| System, Light, Dark; accent color; compact/comfortable density | Implemented |
| VoiceOver labels and values for timer, rows, menu bar item, charts | Implemented |
| Keyboard navigation and shortcuts | Implemented |
| State not conveyed by color alone (badges with text, pause symbol in the menu bar, sync icons with text or help, symbol plus name for every template) | Implemented |
| Reduced motion (timer transition) | Implemented |

### Reliability

| Requirement | Status |
| --- | --- |
| Recovery of open sessions after quit or crash (resume / finish / finish at last seen / cancel) | Implemented |
| Sleep and wake handling (keep running by default; optional pause on sleep) | Implemented |
| Graceful handling of every service failure | Implemented (see [ARCHITECTURE.md](../Architecture/ARCHITECTURE.md#error-handling-summary)) |

### Other

| Item | Status |
| --- | --- |
| App Intents (Start Work, Pause/Resume, Finish Work) | Implemented; not exercised through the Shortcuts app during development |
| Launch at login (`SMAppService`) | Implemented; not exercised during development |
| Existing logo as app icon, About, onboarding | Implemented (1.1.0 regenerates the icon from vector sources on the macOS icon grid; the original `logo.png` is unchanged) |
| DMG installer with branded background and Applications shortcut | Implemented (`scripts/package-dmg.sh`); development-signed, not notarized |
| Documentation grouped under `Documentation/`, with only README.md and CLAUDE.md at the root | Implemented (enforced by `scripts/check-doc-links.sh`) |
| Sidebar: Dashboard, Templates, Work Logs, Calendar, Analytics, Settings, About | Implemented |

## 4. Out of scope for V1 (future)

- **V2:** iCloud sync
- **V3:** iPhone and iPad apps
- **V4:** Apple Watch app

See [ADR-010](../Decisions/ADR-010-future-icloud-compatibility.md) and [ADR-011](../Decisions/ADR-011-core-swift-package.md) for how the architecture prepares for these. None of them are implemented.
