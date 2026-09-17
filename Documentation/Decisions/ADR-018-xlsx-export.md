# ADR-018 — Excel workbook export architecture

Status: Accepted
Date: 2026-09-16

## Context

Users need to export Work Logs to `.xlsx`. Apple frameworks can't write Office Open XML workbooks. The project has no third-party dependencies, and adding one requires an ADR. Export must never change recorded work, must respect the app sandbox, and must handle cancellation and write errors.

## Decision

- **An in-house, minimal SpreadsheetML writer** in `CalendarTimeLoggerKit/Services/Export`:
  - `ZipArchiveWriter`: ZIP container (APPNOTE 6.3), CRC-32, DEFLATE via Foundation's `NSData.compressed(using: .zlib)`, stored entries when compression doesn't help.
  - `XLSXWriter`: content types, relationships, document properties, workbook, styles, and one worksheet per sheet. Inline strings; dates and durations as real Excel serial numbers in the workbook's time zone; XML escaping and removal of XML-invalid characters; the 32,767-character cell limit; sheet name rules; frozen header and filter.
  - `WorkLogWorkbookBuilder`: domain → workbook (Work Logs and Summary sheets). No spreadsheet types leak into domain models.
  - `WorkLogExportService`: reads completed sessions, applies the scope (All, Current Filter, Today, This Week, This Month), builds the workbook before asking for a destination, and writes atomically. Destination (`ExportDestinationProviding`) and writing (`ExportFileWriting`) are protocols, so tests cover cancellation and write failures.
- The app presents an `NSSavePanel`. The sandbox gains `com.apple.security.files.user-selected.read-write` (`ENABLE_USER_SELECTED_FILES = readwrite`), limited to locations the user picks.

## Alternatives considered

- **A third-party XLSX library (for example CoreXLSX, which only reads, or libxlsxwriter).** A C library adds a build dependency and bridging for a small subset of features.
- **CSV.** Not the requested format; dates and durations lose their types.
- **Flat XML Spreadsheet 2003.** Excel warns when opening it, and Numbers and Quick Look support it poorly.

## Consequences

- About 770 lines of focused code (including the export service), covered by 14 tests that read the ZIP back independently (CRC check, inflate, XML parsing). Workbooks were verified in Microsoft Excel (no repair prompt, correct values and formats).
- Only the features the export needs are supported. Formulas, shared strings, and charts aren't implemented.
