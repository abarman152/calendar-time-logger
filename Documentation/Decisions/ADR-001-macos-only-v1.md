# ADR-001 — macOS-only V1

Status: Accepted
Date: 2026-09-15

## Context

Calendar Time Logger's core workflow is starting and finishing work from the desktop where the work happens, with the menu bar as the main control surface. The original Xcode template targeted iOS, iPadOS, visionOS, and macOS at once. Supporting several platforms in V1 would multiply UI, testing, and permission work before the core session model is proven.

## Decision

V1 ships for **macOS 27 only**. The app target's `SUPPORTED_PLATFORMS` is `macosx`, and all iOS and visionOS build settings were removed. No iPhone, iPad, or Watch targets exist. iCloud sync is not implemented.

## Alternatives considered

- **Multiplatform target from day one.** Rejected: MenuBarExtra, Settings scenes, and NSWorkspace sleep handling are macOS-specific, so shared UI would be thin while testing cost doubles.
- **Empty placeholder targets for future platforms.** Rejected: they add maintenance without value and would suggest support that doesn't exist.

## Consequences

- Faster, more focused V1 with native macOS conventions.
- Future platforms need new app targets. To keep that practical, the domain and services live in a platform-neutral package ([ADR-011](ADR-011-core-swift-package.md)) with a sync-friendly model ([ADR-010](ADR-010-future-icloud-compatibility.md)).
