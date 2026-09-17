import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// A template awaiting delete confirmation, held by value so the model can be
/// deleted without the confirmation still reading it.
struct TemplateDeletion: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isInProgress: Bool
}

/// Template list with search, plus the editor for the selected template.
struct TemplatesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: [SortDescriptor(\WorkTemplate.sortOrder), SortDescriptor(\WorkTemplate.createdAt)]) private var allTemplates: [WorkTemplate]
    @State private var searchText = ""
    /// Owned here, above the editor, so confirming never re-renders the editor
    /// of the template being deleted.
    @State private var pendingDeletion: TemplateDeletion?

    private var templates: [WorkTemplate] { allTemplates.filter(\.isLive) }

    var body: some View {
        @Bindable var environment = environment
        let templates = self.templates
        let visible = searchText.trimmingCharacters(in: .whitespaces).isEmpty
            ? templates
            : templates.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.category.localizedCaseInsensitiveContains(searchText)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }

        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("Templates")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        environment.isManageCategoriesPresented = true
                    } label: {
                        Label("Manage Categories", systemImage: WorkCategory.symbolName)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .help("Manage Categories")
                    Button {
                        environment.isNewTemplatePresented = true
                    } label: {
                        Label("New Template", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .help("New Template (⌘N)")
                    .keyboardShortcut("n", modifiers: .command)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                TextField("Search templates", text: $searchText, prompt: Text("Search templates or categories…"))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)

                TemplateList(templates: visible, isFiltered: !searchText.isEmpty, hasTemplates: !templates.isEmpty,
                             searchText: searchText, onMove: move, onDuplicate: duplicate, onDelete: requestDelete)
            }
            .frame(width: 270)
            .background(.background.secondary.opacity(0.5))

            Divider()

            Group {
                if let template = templates.first(where: { $0.id == environment.selectedTemplateID }) {
                    TemplateEditorView(template: template, onDelete: { requestDelete(template) })
                        .id(template.id)
                } else {
                    ContentUnavailableView("Select a Template", systemImage: "square.grid.2x2",
                                           description: Text("Templates describe how a kind of work is recorded: its icon, calendar, tags, menu bar style, and notifications."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Templates")
        .sheet(isPresented: $environment.isNewTemplatePresented) {
            TemplateEditorSheet { created in
                environment.selectedTemplateID = created.id
                environment.isNewTemplatePresented = false
            } onCancel: {
                environment.isNewTemplatePresented = false
            }
        }
        .sheet(isPresented: $environment.isManageCategoriesPresented) {
            ManageCategoriesSheet { environment.isManageCategoriesPresented = false }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { deletion in
            Button("Delete Template", role: .destructive) { delete(deletion) }
        } message: { deletion in
            Text(deletion.isInProgress
                 ? "The session in progress keeps running and is saved as usual. Existing work logs keep their name and icon. This can’t be undone."
                 : "Existing work logs keep their name and icon. This can’t be undone.")
        }
        .onAppear {
            if environment.selectedTemplateID == nil { environment.selectedTemplateID = templates.first?.id }
        }
    }

    private func requestDelete(_ template: WorkTemplate) {
        guard template.isLive else { return }
        pendingDeletion = TemplateDeletion(
            id: template.id,
            name: template.name,
            isInProgress: template.id == environment.sessions.activeSession?.templateID
        )
    }

    /// Deselects the template before deleting it, so its editor is gone by the
    /// time the model is. If the delete fails, the selection comes back.
    private func delete(_ deletion: TemplateDeletion) {
        pendingDeletion = nil
        guard let template = environment.persistence.template(id: deletion.id) else { return }
        let wasSelected = environment.selectedTemplateID == deletion.id
        if wasSelected { environment.selectedTemplateID = nil }
        environment.perform { try environment.persistence.deleteTemplate(template) }
        if wasSelected, environment.persistence.template(id: deletion.id) != nil {
            environment.selectedTemplateID = deletion.id
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = templates
        ordered.move(fromOffsets: source, toOffset: destination)
        environment.perform { try environment.persistence.moveTemplates(ordered) }
    }

    private func duplicate(_ template: WorkTemplate) {
        environment.perform {
            let copy = try environment.persistence.duplicateTemplate(template)
            environment.selectedTemplateID = copy.id
        }
    }
}

private struct TemplateList: View {
    @Environment(AppEnvironment.self) private var environment
    let templates: [WorkTemplate]
    let isFiltered: Bool
    let hasTemplates: Bool
    let searchText: String
    let onMove: (IndexSet, Int) -> Void
    let onDuplicate: (WorkTemplate) -> Void
    let onDelete: (WorkTemplate) -> Void

    var body: some View {
        @Bindable var environment = environment
        List(selection: $environment.selectedTemplateID) {
            ForEach(templates) { template in
                row(template)
            }
            .onMove { source, destination in
                if !isFiltered { onMove(source, destination) }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if let template = templates.first(where: { $0.id == environment.selectedTemplateID }) {
                onDelete(template)
            }
        }
        .overlay {
            if !hasTemplates {
                ContentUnavailableView("No Templates", systemImage: "square.grid.2x2",
                                       description: Text("Click + to create one."))
            } else if templates.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(_ template: WorkTemplate) -> some View {
        HStack(spacing: 10) {
            TemplateIconView(icon: template.symbolName, color: template.color, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(template.name)
                    .lineLimit(1)
                Text(template.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Category, \(template.category)")
            }
            Spacer(minLength: 4)
            PriorityMarkers(priority: template.taskPriority)
            if template.id == environment.sessions.activeSession?.templateID {
                Image(systemName: "record.circle")
                    .foregroundStyle(.green)
                    .accessibilityLabel("In progress")
                    .help("In progress")
            }
        }
        .padding(.vertical, environment.settings.density.rowPadding / 2 + 1)
        .tag(template.id)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button { environment.start(template) } label: { Label("Start Work", systemImage: "play.fill") }
                .disabled(environment.sessions.activeSession != nil)
            Button { environment.selectedTemplateID = template.id } label: { Label("Edit Template", systemImage: "slider.horizontal.3") }
            Button { onDuplicate(template) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive) { onDelete(template) } label: { Label("Delete…", systemImage: "trash") }
        }
    }
}

/// The New Template sheet.
struct TemplateEditorSheet: View {
    let onCreate: (WorkTemplate) -> Void
    let onCancel: () -> Void

    var body: some View {
        // A sheet can't be larger than its window. A fixed frame wider or taller
        // than the window was clipped on both sides and squeezed the scroll
        // area; a flexible one shrinks with the window, and the editor switches
        // to a single column when it is narrow.
        TemplateEditorView(template: nil, onCreate: onCreate, onCancel: onCancel)
            .frame(minWidth: 560, idealWidth: 900, maxWidth: 1000, minHeight: 420, idealHeight: 780, maxHeight: .infinity)
    }
}
