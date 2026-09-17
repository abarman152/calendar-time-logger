# ADR-022 — Task priority as two booleans, captured per session

Status: Accepted
Date: 2026-09-16

## Context

Work needs a classification so the user can see where their time goes beyond “which template”. The classification asked for is the familiar urgent/important pair: each piece of work is urgent or not, and important or not, giving four combinations.

Three questions had to be settled:

1. **What is stored** — the four combinations as a category, or the two booleans.
2. **Who owns the value** — the template, the session, or both.
3. **Whether a running session can change it.**

Recorded work must stay correct: a Work Log is the record of what happened, and editing a template later must never rewrite history ([ADR-004](ADR-004-worksession-source-of-truth.md)).

## Decision

- **Store two booleans, `isUrgent` and `isImportant`**, on both `WorkTemplate` and `WorkSession`. The four combinations are derived (`TaskPriority.quadrant`), never stored. Analytics, filtering, and export can then ask either question independently (“all urgent work”, “urgent and important only”) without a fixed category list in the store.
- **Both values are mandatory and always concrete.** There is no `nil`, unknown, or unconfigured state: the properties are non-optional with a `false` default, so every template, every session, and every record written before 1.2 reads as Not Urgent, Not Important.
- **The template holds defaults; the session holds the truth.** Starting a session copies the template's values onto the session, where they can be changed for that session only. `SessionService.start(template:priority:)` takes the override; `changeTemplate` and `reassignTemplate` deliberately leave the session's priority alone.
- **A running session can change its priority** (`SessionService.updateTaskPriority`), like notes and tags. The Work Log records the values the session ends with. There is no separate audit trail of intermediate values; `modifiedAt` moves, as it does for every other session edit.
- **A completed session can be corrected** through `SessionEdit`, which also refreshes its Calendar event.
- **Calendar keeps the event title as the template name.** Priority goes in the event notes as `Urgent: Yes · Important: No`, because EventKit has no field for it and long titles make calendars unreadable ([ADR-005](ADR-005-calendar-as-derived-representation.md), [ADR-017](ADR-017-calendar-event-color-limitation.md)).
- **Quick tasks reuse the same model.** A Quick New Task is an ordinary `WorkSession` with no `templateID`, its own name, and its own priority — no template is created. Everything downstream (Work Logs, analytics, Calendar, export) treats it like template-started work.

## Persistence

Adding two non-optional attributes with defaults is a lightweight SwiftData migration. `CalendarTimeLoggerSchemaV2` holds the current models, and `CalendarTimeLoggerMigrationPlan` gains a `.lightweight` stage from V1. Existing rows are migrated in place: no template loses its name, icon, color, tags, calendar, notes, menu bar configuration, or notification behavior, and no work log is rewritten.

**Every past version needs its own frozen models.** A migration plan identifies the version a store was written with by matching the store's entity hashes against each `VersionedSchema`. Pointing V1 at the current model types makes V1 and V2 hash identically, so a 1.1 store matches neither and Core Data raises an Objective-C exception inside `migrateStoreWithContext:` — which Swift's `do/catch` cannot catch, so the app aborts on launch. `CalendarTimeLoggerSchemaV1` therefore keeps frozen copies of the 1.1 `WorkTemplate` and `WorkSession` (`Persistence/SchemaV1.swift`), never edited and never used to record work. A future version 3 freezes the V2 shape the same way.

This is covered by `StoreMigrationTests`, which writes a store with the frozen 1.1 models and then opens it through `PersistenceService.open(url:)`. The test was confirmed to fail (abort) against the incorrect plan and to pass against this one.

## Alternatives considered

- **A four-case enum (`TaskPriorityQuadrant`) as the stored value.** Compact, but “how much urgent work did I do?” then needs an `or` across two cases everywhere, and adding a third axis later would mean another migration of stored values.
- **Priority on the template only.** Simpler, but a template's classification is a default, not a fact about a particular afternoon; historical work would change whenever the template changed.
- **Priority fixed at session start.** Safe, but the user often learns a task is urgent *while* doing it, and the value would then be wrong in exactly the case that matters.
- **A separate `TaskMetadata` model.** There is no existing shared metadata type, and two booleans do not justify a new relationship — which would also complicate future CloudKit sync ([ADR-010](ADR-010-future-icloud-compatibility.md)).

## Consequences

- Any combination can be counted without re-deriving categories: `WorkAnalytics.priorityTotals` always returns all four combinations (zero-filled), plus overlapping “urgent (any)” and “important (any)” totals, so an empty range shows zeros rather than a misleading share.
- Because a running session can change its priority, the value in a Work Log is the final one, not the one chosen at start. This is documented in the UI (“The Work Log records the values it ends with”).
- The two booleans are also the export's `Urgent` and `Important` columns, selectable independently ([ADR-023](ADR-023-selectable-export-columns.md)).
