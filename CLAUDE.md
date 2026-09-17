# Working on Calendar Time Logger

Instructions for AI assistants and new contributors. Keep this file at the repository root.

## What this is

A native macOS 27 app (SwiftUI + AppKit edges) that records live work sessions and writes each finished session to Apple Calendar. `WorkSession` is the source of truth; Calendar is a derived representation.

## Repository layout

| Path | Contents |
| --- | --- |
| `CalendarTimeLoggerKit/` | Swift package: domain, persistence, services. **No AppKit or SwiftUI.** |
| `calender_time_logger/` | Xcode project and app target sources (`App/`, `Features/`, `UI/`, `AppIntents/`, `Resources/`) |
| `Documentation/` | All documentation (see `Documentation/README.md`) |
| `scripts/` | Verification, audits, icon and symbol generation, DMG packaging |
| `dist/` | Built DMGs (ignored by version control) |
| `README.md`, `CLAUDE.md` | The only Markdown files at the repository root |
| `LICENSE` | MIT License, copyright Abir Barman |

## Product rules that must not regress

1. Starting a template does **not** create a Calendar event.
2. Finishing a session creates the event from the **real** start and finish timestamps, never a template's default duration.
3. A Calendar failure never loses the work log: save first, sync after.
4. Only events carrying `calendartimelogger://session/<id>` are updated or removed.
5. One open session at a time.
6. No emoji in the UI. Icons are SF Symbols from `SymbolCatalog`.
7. The CTL menu bar item exists while the app runs, whatever the session state.

## Conventions

- Swift 6 language mode, strict concurrency. Services are `@MainActor`; value types are `Sendable`.
- Use the injectable clock (`now: () -> Date`) in service logic; never call `Date()` where tests need control.
- Domain, rules, and formatting go in the package; anything AppKit- or SwiftUI-specific goes in the app target.
- System services (EventKit, UserNotifications) sit behind protocols so tests can mock them.
- User-facing errors conform to `LocalizedError` with a description and a recovery suggestion.
- A view never deletes the SwiftData model it renders. The list that owns the item presents the confirmation, passes identifiers, deselects, then deletes; code that can hold a model past a delete or an `await` checks `isLive` first (see Architecture › App layer).
- No third-party dependencies without an ADR.

## Before you finish a change

```bash
scripts/verify.sh --full     # tests, Debug build, audits, analyzer, Release build, documentation checks
```

- New behavior in the package needs tests (`CalendarTimeLoggerKit/Tests`).
- Update the documentation that owns the change (see `Documentation/Development/DOCUMENTATION_RULES.md`) and add a `CHANGELOG.md` entry.
- Meaningful architectural decisions get an ADR in `Documentation/Decisions/`.
- Verify UI changes by running the app in DEBUG demo mode (`-demo`), which uses an in-memory store and never touches real data or calendars.

## Safety

- The user runs the released app from `/Applications` with real work data. Prefer `-demo` for manual checks, and ask before any run that could write to the real store or to Apple Calendar.
- Scope `pkill`/`pgrep` to the dev build path, not just the app name, so the installed copy isn't quit by accident.
- Regenerating icons or the symbol catalog is done through `scripts/`, never by hand-editing generated files.
