# Architecture Decisions

Calendar Time Logger records significant decisions as Architecture Decision Records (ADRs). The format and the rules for when an ADR is required are in [DOCUMENTATION_RULES.md](../Development/DOCUMENTATION_RULES.md#when-an-adr-is-required).

| ADR | Title | Status |
| --- | --- | --- |
| [ADR-001](ADR-001-macos-only-v1.md) | macOS-only V1 | Accepted |
| [ADR-002](ADR-002-swiftui-primary-ui.md) | SwiftUI as the primary UI framework | Accepted |
| [ADR-003](ADR-003-swiftdata-persistence.md) | SwiftData persistence | Accepted |
| [ADR-004](ADR-004-worksession-source-of-truth.md) | WorkSession as the source of truth; Work Logs as a projection | Accepted |
| [ADR-005](ADR-005-calendar-as-derived-representation.md) | Apple Calendar as a derived representation | Accepted |
| [ADR-006](ADR-006-eventkit-abstraction-and-ownership.md) | EventKit abstraction and event ownership | Accepted |
| [ADR-007](ADR-007-one-active-session.md) | One active session at a time | Accepted |
| [ADR-008](ADR-008-menu-bar-customization.md) | Menu bar customization model | Partly superseded by ADR-016 |
| [ADR-009](ADR-009-wall-clock-vs-active-duration.md) | Wall-clock vs active duration | Accepted |
| [ADR-010](ADR-010-future-icloud-compatibility.md) | Future iCloud compatibility | Accepted |
| [ADR-011](ADR-011-core-swift-package.md) | Core logic in a local Swift package | Accepted |
| [ADR-012](ADR-012-recovery-and-sleep.md) | Session recovery and sleep behavior | Accepted |
| [ADR-013](ADR-013-calendar-selection.md) | Calendar selection and missing calendars | Accepted |
| [ADR-014](ADR-014-sf-symbols-template-icons.md) | SF Symbols as the template icon system | Accepted |
| [ADR-015](ADR-015-persistent-ctl-menu-bar-item.md) | Persistent CTL menu bar identity | Accepted |
| [ADR-016](ADR-016-menu-bar-pill-and-symbol-segments.md) | Menu bar background pill and symbol segments | Accepted |
| [ADR-017](ADR-017-calendar-event-color-limitation.md) | Calendar event color follows the calendar | Accepted |
| [ADR-018](ADR-018-xlsx-export.md) | Excel workbook export architecture | Accepted |
| [ADR-019](ADR-019-app-icon-and-ctl-mark.md) | App icon and CTL mark generated from vector sources | Partly superseded by ADR-024 |
| [ADR-020](ADR-020-dmg-packaging.md) | DMG packaging | Accepted |
| [ADR-021](ADR-021-documentation-structure.md) | Documentation lives in Documentation/ | Accepted |
| [ADR-022](ADR-022-task-priority-model.md) | Task priority as two booleans, captured per session | Accepted |
| [ADR-023](ADR-023-selectable-export-columns.md) | Selectable, orderable export columns | Accepted |
| [ADR-024](ADR-024-flat-icns-app-icon.md) | A flat app icon, delivered as `.icns` | Accepted |
| [ADR-025](ADR-025-work-categories.md) | Categories as a name captured per session | Partly superseded by ADR-027 |
| [ADR-026](ADR-026-calendar-event-boundaries.md) | Calendar event boundary semantics | Accepted |
| [ADR-027](ADR-027-stored-category-list.md) | A stored category list with stable identity | Accepted |
