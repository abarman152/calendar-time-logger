# ADR-023 — Selectable, orderable export columns

Status: Accepted
Date: 2026-09-16

## Context

1.1 exported a fixed 13-column Work Logs sheet ([ADR-018](ADR-018-xlsx-export.md)). Different uses want different sheets: a timesheet needs date, template, and duration; a review of where time goes needs the priority columns and little else. Adding Urgent and Important to a fixed layout would have made the widest sheet wider still.

## Decision

- **`WorkLogExportColumn`** enumerates every exportable field, and owns its header, its width, the one-line explanation shown beside its checkbox, the `SpreadsheetCell` it produces, and the readable text the preview shows. A new column is one case, not a change in three places.
- **`WorkLogColumnSelection`** is an ordered, duplicate-free list of columns. The order *is* the workbook's column order, left to right. It is a value type with `toggle`, `move(fromOffsets:toOffset:)` (SwiftUI `onMove` semantics, implemented without importing SwiftUI into the package), `selectAll`, and `deselectAll`.
- **The selection is persisted** in `SettingsStore.exportColumns` as raw values. Unknown names from a newer version are ignored rather than invalidating the setting.
- **Presets** (`Basic`, `Detailed`, `Priority Analysis`, `Everything`) are convenience selections, not a required step; `WorkLogExportPreset.matching` lets the sheet show which one is in use.
- **An empty selection is an error, not an empty file.** `WorkLogExportError.noColumnsSelected` is returned before the Save panel opens, and the Export button is disabled with an explanation.
- **The preview formats only the rows it shows** (the most recent five), using each column's `previewText`, so what the user checks is what the workbook will contain.
- **Internal identifiers are still never exported.** Session IDs are not offered as a column; the Calendar event identifier remains available because it is Apple Calendar's own reference, not a database key.
- **The Summary sheet is not selectable.** It is a fixed report — totals, work by template, work by task priority, daily and weekly totals — kept or omitted by one switch.

## Alternatives considered

- **Keep a fixed layout and add the two priority columns.** Least work, but the sheet keeps growing and a timesheet still needs manual column deletion in Excel.
- **A checkbox list without ordering.** Simpler UI, but column order is what makes a sheet usable at a glance, and reordering afterwards in Excel is tedious.
- **A saved “export profile” model.** More than the feature needs; one remembered selection covers the repeated case.

## Consequences

- The default selection is the 1.1 layout plus `Urgent` and `Important` after `Template`, so an export made without touching the sheet is a superset of the old one. Anything parsing the old fixed layout by column position must be updated — this is a MINOR, backward-compatible feature, but column positions moved.
- `WorkLogWorkbookBuilder.logSheet` no longer knows about individual fields; it maps the selection. The tests that assert on cell positions assert on the default selection.
- `Task Priority` (the combination in words) is available as a column but off by default, because `Urgent` and `Important` are more useful for filtering and pivoting in Excel.
