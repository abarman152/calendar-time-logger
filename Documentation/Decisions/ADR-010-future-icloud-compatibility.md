# ADR-010 — Future iCloud compatibility

Status: Accepted
Date: 2026-09-15

## Context

iCloud sync (V2) and iPhone, iPad, and Watch apps (V3–V4) are on the roadmap but out of scope for V1. The V1 model shouldn't block them.

## Decision

Design the V1 model within **CloudKit-backed SwiftData constraints**, without enabling sync:

- Every stored property has a default value or is optional.
- No `@Attribute(.unique)` constraints; uniqueness (template names) is enforced in code.
- Stable `UUID` identifiers on every entity; external identifiers (EventKit) are never keys.
- No required relationships (templates are referenced by ID plus a snapshot).
- JSON-encoded configuration blobs tolerate unknown or missing keys.
- A versioned schema and migration plan exist from 1.0.
- The store is explicitly created with `cloudKitDatabase: .none`; there is no iCloud entitlement.

## Alternatives considered

- **Enable CloudKit now.** Out of scope and would need conflict handling for the one-active-session rule and for Calendar ownership across devices.
- **Ignore sync constraints until V2.** Would likely force a disruptive migration.

## Consequences

- V2 can move toward a CloudKit configuration with fewer model changes.
- Open questions for V2 (not solved in V1): which device owns Calendar writes, how open sessions on two devices interact, and whether Calendar event identifiers (which are device-local) should sync.
