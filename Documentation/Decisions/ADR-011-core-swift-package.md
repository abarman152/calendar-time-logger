# ADR-011 — Core logic in a local Swift package

Status: Accepted
Date: 2026-09-15

## Context

The repository started as a single Xcode app target with no test target. Core rules (the state machine, timing, Calendar ownership, and notification scheduling) need fast, reliable tests and must stay free of UI dependencies so future platforms can reuse them.

## Decision

Create **`CalendarTimeLoggerKit`**, a local Swift package (Swift 6 language mode, macOS 27), containing `Domain`, `Persistence`, `Services`, and `Utilities`, plus a Swift Testing test target. The existing Xcode app target depends on it through an `XCLocalSwiftPackageReference`. The package imports no AppKit or SwiftUI.

## Alternatives considered

- **Add an XCTest bundle to the app target.** Tests would need a host app, signing, and a launch, making them slower and flakier. It also wouldn't enforce the "no UI in the domain" boundary.
- **Multiple packages (Domain, Services, Persistence).** Finer boundaries, but more ceremony than a V1 of this size needs.

## Consequences

- `swift test` runs 83 tests in well under a second with no permissions or host.
- The compiler enforces that the domain layer can't touch UI objects.
- A future iOS or watchOS target can link the same package; its services use frameworks available on those platforms.
- Types used by the app must be `public`. Package internals (for example raw JSON storage) stay hidden.
