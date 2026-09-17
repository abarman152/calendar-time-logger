import CalendarTimeLoggerKit
import Observation
import SwiftData
import SwiftUI

enum WorkLogDateRange: String, CaseIterable, Identifiable {
    case all, today, thisWeek, thisMonth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Time"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        }
    }

    func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .all: nil
        case .today: calendar.dateInterval(of: .day, for: now)
        case .thisWeek: calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth: calendar.dateInterval(of: .month, for: now)
        }
    }
}

/// Work Logs search and filter state. Kept on `AppEnvironment` so an export
/// can use the current filter.
@MainActor
@Observable
final class WorkLogFilterState {
    var searchText = ""
    var templateID: UUID?
    var tag: String?
    var status: CalendarSyncStatus?
    var priority: TaskPriorityFilter?
    var category: String?
    var dateRange: WorkLogDateRange = .all

    func filter(now: Date = Date()) -> WorkLogFilter {
        WorkLogFilter(searchText: searchText, templateID: templateID, tag: tag, syncStatus: status,
                      priority: priority, category: category, dateInterval: dateRange.interval(now: now))
    }

    var isActive: Bool { filter().isActive }
    var hasMenuFilters: Bool {
        templateID != nil || tag != nil || status != nil || priority != nil || category != nil || dateRange != .all
    }

    func clearMenuFilters() {
        templateID = nil
        tag = nil
        status = nil
        priority = nil
        category = nil
        dateRange = .all
    }
}

/// A work log that an edit sheet or delete confirmation acts on. It holds the
/// identifier, not the model, so the model can be deleted without anything
/// still rendering it.
struct WorkLogAction: Identifiable, Equatable {
    let id: UUID
    let hasCalendarEvent: Bool

    init(_ log: WorkLog) {
        id = log.id
        hasCalendarEvent = log.hasCalendarEvent
    }
}

/// Completed sessions grouped by day, with search, filters, details, and export.
struct WorkLogsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }, sort: \WorkSession.startedAt, order: .reverse)
    private var sessions: [WorkSession]
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder)]) private var templates: [WorkTemplate]
    @State private var showsInspector = true
    /// The work log in the edit sheet. Owned here rather than by the details
    /// pane so a row's context menu can edit a log that isn't selected.
    @State private var editing: WorkLogAction?
    /// The work log awaiting delete confirmation. The confirmation lives here,
    /// above the details pane, so confirming never re-renders a view that is
    /// showing the deleted model.
    @State private var pendingDeletion: WorkLogAction?

    var body: some View {
        @Bindable var environment = environment
        @Bindable var filters = environment.workLogFilters
        let liveSessions = sessions.filter(\.isLive)
        let allLogs = liveSessions.map { WorkLog(session: $0) }
        let filter = filters.filter()
        let filtered = WorkLogQuery.filter(allLogs, with: filter)
        let groups = WorkLogQuery.groupByDay(filtered)

        List(selection: $environment.selectedWorkLogID) {
            ForEach(groups) { group in
                Section {
                    ForEach(group.logs) { log in
                        WorkLogRow(log: log, isSelected: environment.selectedWorkLogID == log.id)
                            .padding(.vertical, environment.settings.density.rowPadding / 2 + 2)
                            .tag(log.id)
                            .contextMenu { rowMenu(log) }
                    }
                } header: {
                    HStack {
                        Text(DayTitle.text(for: group.day))
                        Spacer()
                        Text(DurationFormatting.short(group.totalActiveDuration))
                            .monospacedDigit()
                    }
                    .font(.headline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.inset)
        .onDeleteCommand {
            if let log = allLogs.first(where: { $0.id == environment.selectedWorkLogID }) {
                pendingDeletion = WorkLogAction(log)
            }
        }
        .overlay {
            if liveSessions.isEmpty {
                ContentUnavailableView("No Work Logs Yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Finished sessions appear here."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: filters.searchText)
            }
        }
        .searchable(text: $filters.searchText, placement: .toolbar, prompt: "Search templates, categories, notes, #tags…")
        .navigationTitle("Work Logs")
        .navigationSubtitle(subtitle(filtered: filtered, all: allLogs, filterActive: filter.isActive))
        .toolbar {
            ToolbarItemGroup {
                filterMenu(allLogs: allLogs)
                Button {
                    environment.requestExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export Work Logs to an Excel workbook (⇧⌘E)")
                .disabled(liveSessions.isEmpty)
                Button {
                    showsInspector.toggle()
                } label: {
                    Label(showsInspector ? "Hide Details" : "Show Details", systemImage: "sidebar.trailing")
                }
                .help(showsInspector ? "Hide details" : "Show details")
            }
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let id = environment.selectedWorkLogID, let session = liveSessions.first(where: { $0.id == id }) {
                    WorkLogDetailView(session: session) {
                        editing = WorkLogAction(WorkLog(session: session))
                    } onDelete: {
                        pendingDeletion = WorkLogAction(WorkLog(session: session))
                    }
                    .id(session.id)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "list.bullet.rectangle",
                                           description: Text("Select a work log to see its details."))
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
        }
        .sheet(item: $editing) { action in
            if let session = environment.persistence.session(id: action.id), session.isLive {
                WorkLogEditSheet(session: session) { editing = nil }
            }
        }
        .confirmationDialog("Delete this work log?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { action in
            if action.hasCalendarEvent {
                Button("Delete and Remove Calendar Event", role: .destructive) { delete(action, removingEvent: true) }
                Button("Delete, Keep Calendar Event", role: .destructive) { delete(action, removingEvent: false) }
            } else {
                Button("Delete Work Log", role: .destructive) { delete(action, removingEvent: false) }
            }
        } message: { _ in
            Text("This permanently removes the recorded session. Only the event Calendar Time Logger created can be removed from Calendar.")
        }
    }

    /// Deselects the work log before deleting it, so the details pane is gone
    /// by the time the model is. If the delete fails (for example, its Calendar
    /// event couldn't be removed), the selection comes back.
    private func delete(_ action: WorkLogAction, removingEvent: Bool) {
        pendingDeletion = nil
        guard let session = environment.persistence.session(id: action.id) else { return }
        let wasSelected = environment.selectedWorkLogID == action.id
        if wasSelected { environment.selectedWorkLogID = nil }
        environment.perform {
            try environment.sessions.delete(session, removingCalendarEvent: removingEvent)
        }
        if wasSelected, environment.persistence.session(id: action.id) != nil {
            environment.selectedWorkLogID = action.id
        }
    }

    private func subtitle(filtered: [WorkLog], all: [WorkLog], filterActive: Bool) -> String {
        let total = DurationFormatting.short(WorkAnalytics.totalActiveDuration(filtered))
        let count = filtered.count == 1 ? "1 session" : "\(filtered.count) sessions"
        return filterActive ? "\(count) of \(all.count) · \(total) total" : "\(count) · \(total) total"
    }

    @ViewBuilder
    private func rowMenu(_ log: WorkLog) -> some View {
        Button { environment.selectedWorkLogID = log.id; showsInspector = true } label: {
            Label("Show Details", systemImage: "sidebar.trailing")
        }
        Button { editing = WorkLogAction(log) } label: {
            Label("Edit Entry…", systemImage: "pencil")
        }
        if log.calendarSyncStatus == .synced {
            Button { environment.openCalendarApp() } label: { Label("View in Calendar", systemImage: "calendar") }
        }
        Divider()
        Button(role: .destructive) { pendingDeletion = WorkLogAction(log) } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    private func filterMenu(allLogs: [WorkLog]) -> some View {
        @Bindable var filters = environment.workLogFilters
        return Menu {
            Picker(selection: $filters.dateRange) {
                ForEach(WorkLogDateRange.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Date", systemImage: "calendar")
            }
            Picker(selection: $filters.templateID) {
                Text("All Templates").tag(UUID?.none)
                ForEach(templates) { template in
                    Label(template.name, systemImage: template.symbolName).tag(UUID?.some(template.id))
                }
            } label: {
                Label("Template", systemImage: "square.grid.2x2")
            }
            Picker(selection: $filters.category) {
                Text("All Categories").tag(String?.none)
                ForEach(WorkLogQuery.allCategories(in: allLogs), id: \.self) { name in
                    Label(name, systemImage: WorkCategory.symbolName).tag(String?.some(name))
                }
            } label: {
                Label("Category", systemImage: WorkCategory.symbolName)
            }
            Picker(selection: $filters.tag) {
                Text("All Tags").tag(String?.none)
                ForEach(WorkLogQuery.allTags(in: allLogs), id: \.self) { Text("#\($0)").tag(String?.some($0)) }
            } label: {
                Label("Tag", systemImage: "tag")
            }
            Picker(selection: $filters.priority) {
                Text("All Priorities").tag(TaskPriorityFilter?.none)
                ForEach(TaskPriorityFilter.allCases) { Text($0.title).tag(TaskPriorityFilter?.some($0)) }
            } label: {
                Label("Task Priority", systemImage: PrioritySymbols.section)
            }
            Picker(selection: $filters.status) {
                Text("Any Status").tag(CalendarSyncStatus?.none)
                ForEach(CalendarSyncStatus.allCases, id: \.self) { Text($0.displayName).tag(CalendarSyncStatus?.some($0)) }
            } label: {
                Label("Calendar", systemImage: "calendar.badge.checkmark")
            }
            Divider()
            Button("Clear Filters") { filters.clearMenuFilters() }
                .disabled(!filters.hasMenuFilters)
        } label: {
            Label("Filter", systemImage: filters.hasMenuFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter work logs")
        .accessibilityLabel(filters.hasMenuFilters ? "Filter, active" : "Filter")
    }
}

private struct WorkLogRow: View {
    let log: WorkLog
    let isSelected: Bool

    var body: some View {
        // One line when the list is wide; two lines when the inspector leaves it
        // narrow, so the name, duration, and priority are never squeezed out.
        ViewThatFits(in: .horizontal) {
            wideRow
            compactRow
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(log.templateName), \(log.startedAt.shortTime) to \(log.endedAt.shortTime), \(DurationFormatting.spoken(log.activeDuration)) active. Category, \(log.category). \(log.taskPriority.accessibilityLabel) \(log.calendarSyncStatus.displayName)")
    }

    private var compactRow: some View {
        HStack(alignment: .top, spacing: 10) {
            TemplateIconView(icon: log.templateIcon, color: log.templateColor, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.templateName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    PriorityMarkers(priority: log.taskPriority)
                    Spacer(minLength: 4)
                    Text(DurationFormatting.short(log.activeDuration))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text("\(log.startedAt.shortTime) – \(log.endedAt.shortTime)")
                        .monospacedDigit()
                        .fixedSize()
                    Text(log.category)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SyncStatusLabel(status: log.calendarSyncStatus, compact: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 0)
    }

    private var wideRow: some View {
        HStack(spacing: 12) {
            Text("\(log.startedAt.shortTime) – \(log.endedAt.shortTime)")
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 150, alignment: .leading)
            HStack(spacing: 8) {
                TemplateIconView(icon: log.templateIcon, color: log.templateColor, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(log.templateName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .fixedSize()
                    Text(log.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            // Priority and tags yield space to the template name; tags are
            // dropped first, then priority chips fall back to symbols.
            ViewThatFits(in: .horizontal) {
                PriorityChips(priority: log.taskPriority)
                PriorityMarkers(priority: log.taskPriority)
            }
            ViewThatFits(in: .horizontal) {
                TagChips(tags: Array(log.tags.prefix(2)))
                TagChips(tags: Array(log.tags.prefix(1)))
                Color.clear.frame(width: 0)
            }
            if !log.notes.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                    .help(log.notes)
                    .accessibilityLabel("Has notes")
            }
            Spacer()
            Text(DurationFormatting.short(log.activeDuration))
                .monospacedDigit()
                .fontWeight(.semibold)
                .fixedSize()
                .layoutPriority(2)
            SyncStatusLabel(status: log.calendarSyncStatus, compact: true)
                .frame(width: 20)
        }
    }
}
