import AppKit
import CalendarTimeLoggerKit
import SwiftUI
import UniformTypeIdentifiers

/// Chooses the export scope and columns, previews the result, then saves an
/// Excel workbook through the Save panel.
struct ExportWorkLogsView: View {
    @Environment(AppEnvironment.self) private var environment
    let onClose: () -> Void

    @State private var scope: WorkLogExportScope = .all
    @State private var columns: WorkLogColumnSelection = .default
    @State private var includesSummary = true
    @State private var isExporting = false
    @State private var errorMessage: String?
    @State private var tab: Tab = .columns

    private enum Tab: String, CaseIterable, Identifiable {
        case columns, preview
        var id: String { rawValue }
        var title: String { self == .columns ? "Columns" : "Preview" }
    }

    var body: some View {
        let filterActive = environment.workLogFilters.isActive
        let scopes = WorkLogExportScope.available(filterIsActive: filterActive)
        let preview = (try? environment.exporter.preview(scope: scope, filter: environment.workLogFilters.filter(), columns: columns))

        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Form {
                Picker("Scope", selection: $scope) {
                    ForEach(scopes) { scope in
                        Text(scope == .currentFilter ? "Current Filter (\(filterDescription))" : scope.title).tag(scope)
                    }
                }
                LabeledContent("Format") {
                    Label("Excel Workbook (.xlsx)", systemImage: "doc.richtext")
                }
                LabeledContent("Sessions") {
                    Text(sessionCount(preview?.total ?? 0))
                        .monospacedDigit()
                        .foregroundStyle((preview?.total ?? 0) == 0 ? .secondary : .primary)
                }
                Toggle("Include a Summary sheet", isOn: $includesSummary)
                    .help("Totals by template, task priority, day, and week")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 186)

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)

            Group {
                switch tab {
                case .columns: columnEditor
                case .preview: previewTable(preview)
                }
            }
            .frame(height: 260)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer(count: preview?.total ?? 0)
        }
        .frame(width: 620)
        .onAppear {
            let preferred = environment.settings.exportScope
            scope = scopes.contains(preferred) ? preferred : .all
            if filterActive, environment.exportPrefersCurrentFilter { scope = .currentFilter }
            includesSummary = environment.settings.exportIncludesSummary
            columns = environment.settings.exportColumns
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tablecells")
                .font(.system(size: 26))
                .foregroundStyle(.green)
                .frame(width: 44, height: 44)
                .background(.green.opacity(0.14), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Work Logs")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Completed sessions are saved as an Excel workbook. Your work logs aren’t changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: Columns

    private var columnEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(WorkLogExportPreset.allCases) { preset in
                        Button(preset.title) { columns = preset.selection }
                    }
                    Divider()
                    Button("Default Columns") { columns = .default }
                } label: {
                    Label(WorkLogExportPreset.matching(columns)?.title ?? "Presets", systemImage: "square.grid.2x2")
                }
                .menuStyle(.button)
                .fixedSize()
                Spacer()
                Button("Select All") { columns.selectAll() }
                    .disabled(columns.count == WorkLogExportColumn.allCases.count)
                Button("Deselect All") { columns.deselectAll() }
                    .disabled(columns.isEmpty)
            }
            .controlSize(.small)

            // Selected columns come first, in export order and draggable; the
            // rest follow as unchecked rows.
            List {
                Section("Included — drag to reorder") {
                    ForEach(columns.columns) { column in
                        columnRow(column, isSelected: true)
                    }
                    .onMove { source, destination in
                        columns.move(fromOffsets: source, toOffset: destination)
                    }
                    if columns.isEmpty {
                        Text("No columns selected. Choose at least one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                let remaining = WorkLogExportColumn.allCases.filter { !columns.contains($0) }
                if !remaining.isEmpty {
                    Section("Not Included") {
                        ForEach(remaining) { column in
                            columnRow(column, isSelected: false)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    private func columnRow(_ column: WorkLogExportColumn, isSelected: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in columns.toggle(column) }
        )) {
            HStack(spacing: 8) {
                Text(column.title)
                Text(column.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(column.title)
        .accessibilityHint(column.detail)
    }

    // MARK: Preview

    @ViewBuilder
    private func previewTable(_ preview: (headers: [String], rows: [[String]], total: Int)?) -> some View {
        if columns.isEmpty {
            ContentUnavailableView("No Columns Selected", systemImage: "tablecells",
                                   description: Text("Choose at least one column to export."))
        } else if let preview, preview.rows.isEmpty {
            ContentUnavailableView("No Work Logs", systemImage: "list.bullet.rectangle",
                                   description: Text("There are no completed sessions in this scope. The workbook would contain only column headers."))
        } else if let preview {
            VStack(alignment: .leading, spacing: 6) {
                Text(preview.total <= preview.rows.count
                     ? "All \(sessionCount(preview.total))"
                     : "Last \(preview.rows.count) of \(sessionCount(preview.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            ForEach(Array(preview.headers.enumerated()), id: \.offset) { _, title in
                                Text(title).font(.caption.weight(.semibold))
                            }
                        }
                        Divider()
                        ForEach(Array(preview.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                                    Text(value.isEmpty ? "—" : value)
                                        .font(.caption)
                                        .foregroundStyle(value.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .background(.background.secondary, in: .rect(cornerRadius: Metrics.controlCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius).strokeBorder(Color.primary.opacity(0.1)))
                .accessibilityLabel("Export preview")
            }
        } else {
            ContentUnavailableView("Preview Unavailable", systemImage: "tablecells",
                                   description: Text("The work logs couldn’t be read."))
        }
    }

    // MARK: Footer

    private func footer(count: Int) -> some View {
        HStack {
            if count == 0 {
                Text("An empty workbook will contain only column headers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(columns.count) \(columns.count == 1 ? "column" : "columns") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button(isExporting ? "Exporting…" : "Export…") { export() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting || columns.isEmpty)
                .help(columns.isEmpty ? "Choose at least one column" : "Choose where to save the workbook")
        }
        .padding(20)
    }

    private func sessionCount(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }

    private var filterDescription: String {
        let filters = environment.workLogFilters
        var parts: [String] = []
        if !filters.searchText.trimmingCharacters(in: .whitespaces).isEmpty { parts.append("“\(filters.searchText)”") }
        if filters.dateRange != .all { parts.append(filters.dateRange.title) }
        if let id = filters.templateID, let template = environment.persistence.template(id: id) { parts.append(template.name) }
        if let tag = filters.tag { parts.append("#\(tag)") }
        if let priority = filters.priority { parts.append(priority.title) }
        if let status = filters.status { parts.append(status.displayName) }
        return parts.joined(separator: ", ")
    }

    private func export() {
        isExporting = true
        errorMessage = nil
        let filter = environment.workLogFilters.filter()
        let selection = columns
        Task {
            let outcome = await environment.exporter.export(scope: scope, filter: filter, columns: selection,
                                                            includesSummary: includesSummary,
                                                            destination: SavePanelDestination())
            isExporting = false
            switch outcome {
            case .cancelled:
                break
            case .exported(let url, let count):
                environment.settings.exportIncludesSummary = includesSummary
                environment.settings.exportColumns = selection
                if scope != .currentFilter { environment.settings.exportScope = scope }
                environment.exportFinished(url: url, sessionCount: count)
                onClose()
            case .failed(let error):
                errorMessage = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
            }
        }
    }
}

/// Presents the system Save panel for an `.xlsx` file.
@MainActor
final class SavePanelDestination: ExportDestinationProviding {
    func chooseDestination(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Work Logs"
        panel.prompt = "Export"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }
}
