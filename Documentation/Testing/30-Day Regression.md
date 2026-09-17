# 30-Day Regression

A month of realistic use, compressed into a test that runs in about a second, plus a manual pass over the same kind of data in the running app. Written for 1.3.0, which added categories.

## Purpose

Categories, task priority, Calendar sync, analytics, and export all depend on data that builds up over weeks: templates are edited, categories are renamed, sessions cross midnight, the app is quit with work running. A bug in any of those shows up as wrong history, not as a crash. This regression checks that after thirty consecutive days:

- every session keeps the category, priority, times, and active duration it was recorded with;
- template edits and category renames never rewrite earlier work logs;
- Analytics, filters, search, and the Excel export agree with what was actually recorded;
- nothing is lost across relaunches, including a session left running.

## Test environment

| Item | Value |
| --- | --- |
| Test | `ThirtyDayRegressionTests.thirtyDays` in `CalendarTimeLoggerKit/Tests/CalendarTimeLoggerKitTests/ThirtyDayRegressionTests.swift` |
| Run with | `cd CalendarTimeLoggerKit && swift test --filter ThirtyDayRegressionTests` |
| Services | The real `PersistenceService`, `SessionService`, `CalendarService`, `NotificationService`, `MenuBarService`, `WorkAnalytics`, `WorkLogQuery`, and `WorkLogExportService` |
| Store | A SwiftData store **on disk**, opened with the shipping schema and migration plan |
| Clock | `TestClock`, injected into every service, moved through 2026-08-01 … 2026-08-30 |
| Toolchain | Xcode 27.0 beta, Swift 6.4, macOS 27 |

## Isolated data strategy

The user's real data is never touched:

- The store is a new file in the process's temporary directory (`ctl-30-day-<UUID>.store`), deleted with its journal files when the test ends.
- Settings live in a throwaway `UserDefaults` suite named per run.
- Apple Calendar is replaced by `MockCalendarProvider`, which keeps events in memory, so no event is written to a real calendar.
- Notifications go to `MockNotificationScheduler`.
- The package tests run outside the app sandbox and never open the app container.

## Dataset

Thirty consecutive calendar days, each with at least one completed session, generated through the session engine rather than inserted directly, so every timestamp, pause, and Calendar event is the app's own result.

| Property | Contents |
| --- | --- |
| Templates | The five defaults (Development, Education, Research, Content, Design) plus a new **Client Project** template in Development, created on day 1 and edited on day 15 |
| Categories used | Development, Education, Research, Content, Design, and later **Professional Work** and **Learning**, plus **Operations** chosen for one session on day 30 |
| Priority | All four combinations of Urgent and Important, from template defaults and from per-session overrides |
| Session shapes | Short (35 min) to long (4 h 20 min wall clock); none, one, or two pauses; a session from 23:20 to 01:00 across midnight |
| Other records | A quick task, a cancelled session, notes appended during sessions, tags from templates and quick tasks, a Calendar event for every completed session |
| Size | 63 completed sessions and 1 cancelled session (asserted by the test) |

An independent **ledger** records what each scenario did (template, category, start, end, active minutes, priority), computed from the scenario's own inputs, never read back from the app. Every check below compares the app's figures with the ledger.

## Scenarios

| Days | Scenario | Checked |
| --- | --- | --- |
| 1 | Seed the default templates; create Client Project in Development, Urgent + Important; Start Work; Finish Work | Default categories; the session inherits Development; **no Calendar event exists while working**; Finish Work creates one event with the real 09:00–10:30 times, a `Category: Development` note line, and the ownership URL; the CTL item shows the identity when idle |
| 2–7 | Two or three sessions a day across templates, cycling through all four priority combinations; a quick task in Development; a session started by mistake and cancelled; a Design session recorded as Content | Per-session priority and category overrides; the cancelled session has no event and never appears in Work Logs or analytics |
| 8–14 | Engineering sessions with two pauses each, two of them over four hours; a study session with a pause every day; a research session from 23:20 to 01:00 | Menu bar shows the session while working, the paused indicator while paused, and CTL after Finish Work; each session keeps two pauses; the late session counts toward the day it started |
| 15–21 | Client Project moved to **Professional Work** (day 15); **Education** renamed to **Learning** (day 18); a Writing session moved to Research while running (day 20) | Every session recorded before the edits keeps its category; the rename changes exactly one template and no session; later sessions use the new names; the moved session's inherited category follows Research |
| 22–28 | Daily sessions, then on day 28: analytics, filters, search, and export | See **Analytics and export checks** |
| 29 | A Research session starts at 19:00 and the app goes away at 19:25 with it running; the store is reopened | All 60 sessions completed so far reopen with their category, priority, start, end, and active duration; the cancelled session is still cancelled; template categories are as edited; the open session is offered for recovery, resumed, and finished at 20:00 |
| 30 | Reopen again; create **Release Notes** with category typed as `content`; start Client Project with category **Operations** and priority Urgent only; pause; resume; change priority to Urgent + Important; change template to Writing; add a note; Finish Work; then a Release Notes session; analytics and export again | No recovery prompt after a clean finish; `content` joins the existing **Content**; the chosen **Operations** survives Change Template; 80 minutes active of a 90-minute span; a Calendar event; CTL returns; 30 distinct days recorded |

### Analytics and export checks (days 28 and 30)

- **Category totals** for Today, Last 7 Days, and Last 30 Days: the number of categories, each category's active time, session count, and share, shares summing to 100%, and, inside each category, template totals and all four priority totals adding up to the category and matching the ledger's session counts per combination.
- **Filters and search**: the Development filter (typed in lower case), Urgent within Research, a search for `Professional`, and a search for a note's text each return exactly the ledger's count.
- **Excel export**: a real workbook with the columns Date, Template, Category, Duration, Urgent, Important in that order, and nothing after them. Every row, oldest first, has the ledger's template name, category, wall-clock duration, and Yes/No values. The workbook's parts are well-formed XML and it builds in under 5 seconds.

## Performance

`ThirtyDayRegressionTests.analyticsPerformance` aggregates 20,000 logs across 7 categories. `categoryTotals` makes one grouping pass, then totals each group, and completes well under the 2-second limit. The Analytics screen projects its completed sessions once per render, shares that projection across every section, and limits it to the selected range before grouping by category.

## Manual pass in the running app

The DEBUG demo build seeds 30 consecutive days of the same kind of work (see [DEVELOPMENT.md](../Development/DEVELOPMENT.md#demo-mode-debug-only)) in an in-memory store with sample calendars, so the real store and calendars are never opened. The following were exercised in it on 2026-09-16:

| Area | Result |
| --- | --- |
| Dashboard idle and active | Category beside the start time and in each Today's Work row |
| Templates | Category under each template name; Category picker in Basic Information; Manage Categories sheet with counts |
| Start Work, Quick New Task, Change Category and Priority sheets | Category preselected from the template (General for a quick task), aligned with the priority controls |
| Menu bar popover idle, active, inline quick task, inline category and priority editor | Category shown and editable |
| Work Logs | Category under each template name; Category row in the inspector (synced and Sync Failed) |
| Analytics, This Week and Last 30 Days | Work by Category chart, rows, and the expanded Templates and Task Priority by Category breakdown |
| Work Completed | Category row |
| Export sheet | Category column after Template in the default selection |

Screenshots from this pass are in [Design/Screenshots](../Design/Screenshots) and are used throughout the [User Guide](../User%20Guide/README.md).

![Analytics for the last 30 days of demo data, showing Work by Category](../Design/Screenshots/10-analytics-category.png)

## Results

| Measure | Result |
| --- | --- |
| Automated scenarios (days 1–30) | 7 scenario groups, all passed |
| Assertions failed | 0 |
| Regression found and fixed during development | 4 (below) |
| Falsification | With `renameCategory` altered to also rewrite sessions, the test failed on the history check for every affected session and on the category counts; restoring the code made it pass again |

### Failures found and fixed

| Problem | Fix |
| --- | --- |
| A category typed in a different case than a built-in (`EDUCATION`) was stored as typed when no template used the built-in yet, creating a near-duplicate | Canonical spelling now considers built-in categories as well as templates, for templates and for sessions |
| The demo seed recorded every session in **General**, so Analytics showed one category | Demo sessions now take their template's category |
| The demo build read the real calendar list, so screenshots of the template editor and Calendar screen could expose personal calendar names | Demo mode now uses an in-memory provider with sample calendars |
| The demo seed always included a failed Calendar sync, which showed a warning banner and a sidebar badge on every demo launch | The failure is now opt-in with `-demoSyncFailure` |

## Final status

**Passed.** 193 tests in 21 suites pass, including this regression. See the verification logs in [TESTING.md](TESTING.md) for the full run.

---

[Back to Testing](TESTING.md)
