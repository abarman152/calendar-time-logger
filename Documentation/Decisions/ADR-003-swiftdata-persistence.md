# ADR-003 — SwiftData persistence

Status: Accepted
Date: 2026-09-15

## Context

Templates and sessions must persist locally and survive crashes. Starting a session must save immediately. The model should be able to move to CloudKit later without a rewrite.

## Decision

- Use **SwiftData** with a versioned schema (`CalendarTimeLoggerSchemaV1`) and a migration plan.
- `WorkTemplate` and `WorkSession` are `@Model` classes and serve as the domain entities. Pure value types (`SessionTiming`, `MenuBarConfiguration`, `NotificationBehavior`, `WorkLog`) hold the logic.
- Value-type configurations and pause intervals are stored as **JSON `Data`** behind typed accessors, with tolerant decoding.
- Every mutation calls `save()` explicitly. If a save fails, the in-memory values are restored.
- If the on-disk store can't be opened, fall back to an in-memory store, surface the error, and **refuse to start sessions**.

## Alternatives considered

- **Separate DTO layer mapping value-type domain models to persistence records.** Cleaner separation, but doubles the model code and loses `@Query` ergonomics. Keeping the logic in pure value types gives most of the testability benefit.
- **Core Data.** More mature, but more boilerplate and less idiomatic with SwiftUI.
- **SwiftData composite (Codable struct) attributes.** Avoided because of past reliability issues with nested enums and optionals. JSON `Data` is predictable.
- **A file-based JSON store.** Loses querying and needs hand-built crash safety.

## Consequences

- `@Query` can drive views directly. Raw state fields are publicly readable (`stateRawValue`) for predicates but only settable inside the package.
- Configuration fields can't be queried with predicates, which V1 doesn't need.
- Tests run against real SwiftData in memory.
