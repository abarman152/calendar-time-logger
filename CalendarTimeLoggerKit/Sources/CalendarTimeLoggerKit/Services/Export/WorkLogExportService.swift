import Foundation

/// Chooses where an export is saved. The app shows a Save panel; tests return
/// a fixed URL or `nil` for cancellation.
@MainActor
public protocol ExportDestinationProviding: AnyObject {
    /// Returns the chosen file URL, or `nil` if the user cancelled.
    func chooseDestination(suggestedName: String) async -> URL?
}

/// Writes export data to disk.
public protocol ExportFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

/// Writes atomically, so a failed export never leaves a partial file.
public struct AtomicFileWriter: ExportFileWriting {
    public init() {}
    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public enum WorkLogExportError: Error, Equatable, LocalizedError, Sendable {
    case noColumnsSelected
    case invalidData(String)
    case permissionDenied(String)
    case diskFull
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noColumnsSelected: "No columns are selected, so there is nothing to export."
        case .invalidData: "The work logs couldn’t be converted to an Excel workbook."
        case .permissionDenied(let name): "Calendar Time Logger doesn’t have permission to save “\(name)”."
        case .diskFull: "There isn’t enough disk space to save the export."
        case .writeFailed: "The Excel workbook couldn’t be saved."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noColumnsSelected: "Choose at least one column in the export sheet, then try again."
        case .invalidData(let reason): "\(reason) Your work logs weren’t changed."
        case .permissionDenied: "Choose a different folder, such as Documents or Desktop, and try again."
        case .diskFull: "Free up some space and try again."
        case .writeFailed(let reason): "\(reason) Your work logs weren’t changed."
        }
    }
}

public enum WorkLogExportOutcome: Equatable, Sendable {
    case exported(url: URL, sessionCount: Int)
    case cancelled
    case failed(WorkLogExportError)
}

/// Exports completed work logs to an Excel workbook.
///
/// Export only reads sessions; it never modifies or deletes them.
@MainActor
public final class WorkLogExportService {
    private let persistence: PersistenceService
    private let calendarName: (String?) -> String?
    private let writer: ExportFileWriting
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        persistence: PersistenceService,
        calendarName: @escaping (String?) -> String?,
        writer: ExportFileWriting = AtomicFileWriter(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.calendarName = calendarName
        self.writer = writer
        self.calendar = calendar
        self.now = now
    }

    /// Completed sessions in the scope, oldest first. Cancelled and open
    /// sessions are never exported.
    public func records(scope: WorkLogExportScope, filter: WorkLogFilter?) throws -> [WorkLogExportRecord] {
        let sessions = try persistence.completedSessions()
        var logs = sessions.map { WorkLog(session: $0) }
        if scope == .currentFilter, let filter {
            logs = WorkLogQuery.filter(logs, with: filter)
        } else if let interval = scope.interval(now: now(), calendar: calendar) {
            logs = WorkAnalytics.logs(logs, in: interval)
        }
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        return logs
            .map { log in
                let session = byID[log.id]
                return WorkLogExportRecord(
                    log: log,
                    calendarName: calendarName(session?.eventCalendarIdentifier ?? session?.calendarIdentifier) ?? "",
                    calendarEventIdentifier: session?.calendarEventIdentifier ?? ""
                )
            }
            .sorted { $0.log.startedAt < $1.log.startedAt }
    }

    public func workbookData(
        scope: WorkLogExportScope,
        filter: WorkLogFilter?,
        columns: WorkLogColumnSelection = .default,
        includesSummary: Bool
    ) throws -> (data: Data, count: Int) {
        guard !columns.isEmpty else { throw WorkLogExportError.noColumnsSelected }
        let generatedAt = now()
        let records = try records(scope: scope, filter: filter)
        let workbook = WorkLogWorkbookBuilder.workbook(records: records, columns: columns, scopeTitle: scope.title,
                                                       generatedAt: generatedAt, includesSummary: includesSummary, calendar: calendar)
        let writer = XLSXWriter(timeZone: calendar.timeZone, generatedAt: generatedAt)
        return (try writer.data(for: workbook), records.count)
    }

    /// The first rows of an export, as readable text, for the preview in the
    /// export sheet. Only `limit` records are formatted, whatever the scope
    /// holds.
    public func preview(
        scope: WorkLogExportScope,
        filter: WorkLogFilter?,
        columns: WorkLogColumnSelection,
        limit: Int = 5
    ) throws -> (headers: [String], rows: [[String]], total: Int) {
        let records = try records(scope: scope, filter: filter)
        let selected = columns.columns
        let rows = records.suffix(max(0, limit)).map { record in
            selected.map { $0.previewText(for: record, calendar: calendar) }
        }
        return (selected.map(\.title), rows, records.count)
    }

    /// `Work Logs 2026-09-16.xlsx`, dated in the user's calendar (not UTC).
    public func suggestedFileName(scope: WorkLogExportScope) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: now())
        let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        let suffix = scope == .all ? "" : " (\(scope.title))"
        return "Work Logs \(date)\(suffix).xlsx"
    }

    /// Builds the workbook, asks for a destination, and writes the file.
    public func export(
        scope: WorkLogExportScope,
        filter: WorkLogFilter?,
        columns: WorkLogColumnSelection = .default,
        includesSummary: Bool,
        destination: ExportDestinationProviding
    ) async -> WorkLogExportOutcome {
        // Build first, so a data problem is reported before the Save panel.
        let built: (data: Data, count: Int)
        do {
            built = try workbookData(scope: scope, filter: filter, columns: columns, includesSummary: includesSummary)
        } catch let error as WorkLogExportError {
            return .failed(error)
        } catch let error as XLSXWriterError {
            return .failed(.invalidData(String(describing: error)))
        } catch {
            return .failed(.invalidData(error.localizedDescription))
        }

        guard var url = await destination.chooseDestination(suggestedName: suggestedFileName(scope: scope)) else {
            return .cancelled
        }
        if url.pathExtension.lowercased() != "xlsx" { url.appendPathExtension("xlsx") }

        do {
            try writer.write(built.data, to: url)
            return .exported(url: url, sessionCount: built.count)
        } catch {
            return .failed(Self.map(error, url: url))
        }
    }

    static func map(_ error: Error, url: URL) -> WorkLogExportError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError:
                return .permissionDenied(url.lastPathComponent)
            case NSFileWriteOutOfSpaceError:
                return .diskFull
            default: break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case Int(EACCES), Int(EPERM), Int(EROFS): return .permissionDenied(url.lastPathComponent)
            case Int(ENOSPC): return .diskFull
            default: break
            }
        }
        return .writeFailed(nsError.localizedDescription)
    }
}
