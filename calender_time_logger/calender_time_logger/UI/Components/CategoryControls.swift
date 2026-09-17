import CalendarTimeLoggerKit
import SwiftData
import SwiftUI

/// Chooses a category from the stored list, or names a new one in place.
///
/// The selection always holds a name; there is no empty choice. The picker
/// follows the category it shows: when that category is renamed, the selection
/// takes the new name, and when it is deleted, a template's selection falls
/// back (`fallback`) while a session's keeps the name it was recorded with
/// (`keepsUnlisted`).
struct CategoryPicker: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var records: [WorkCategoryRecord]
    @Binding var selection: String
    var compact = false
    /// Sessions and work logs may carry a category that has since been deleted;
    /// it stays selected and is listed separately. Templates can't.
    var keepsUnlisted = false
    /// The category to use when the selected one is deleted.
    var fallback: () -> String = { WorkCategory.defaultName }

    @State private var isNaming = false
    @State private var newName = ""
    @State private var errorMessage: String?
    /// The record the selection was last matched to, so a rename can be followed.
    @State private var trackedID: UUID?
    @FocusState private var nameIsFocused: Bool

    private static let newTag = "\u{0}new-category"

    private var names: [String] {
        WorkCategory.sorted(records.filter(\.isLive).map(\.name))
    }

    private var unlistedSelection: String? {
        names.contains { WorkCategory.matches($0, selection) } ? nil : WorkCategory.stored(selection)
    }

    /// Changes whenever a category is added, renamed, or deleted.
    private var recordSignature: [String] {
        records.filter(\.isLive).map { "\($0.id)|\($0.name)" }.sorted()
    }

    var body: some View {
        Group {
            if isNaming {
                namingField
            } else {
                menu
            }
        }
        .onAppear(perform: track)
        .onChange(of: selection) { track() }
        .onChange(of: recordSignature) { resolveSelection() }
    }

    private var namingField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("New Category", text: $newName, prompt: Text("Category name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($nameIsFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .frame(minWidth: 140)
                    .accessibilityLabel("New category name")
                Button("Add", action: commit)
                    .disabled((try? WorkCategory.validate(newName)) == nil)
                Button("Cancel", action: cancel)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .controlSize(compact ? .small : .regular)
        .onAppear { nameIsFocused = true }
    }

    private var menu: some View {
        Picker("Category", selection: Binding(
            get: { names.first { WorkCategory.matches($0, selection) } ?? WorkCategory.stored(selection) },
            set: { value in
                if value == Self.newTag {
                    newName = ""
                    errorMessage = nil
                    isNaming = true
                } else {
                    selection = value
                }
            }
        )) {
            ForEach(names, id: \.self) { name in
                Label(name, systemImage: WorkCategory.symbolName).tag(name)
            }
            if let unlisted = unlistedSelection {
                Divider()
                Label("\(unlisted) (deleted)", systemImage: CategorySymbols.deleted).tag(unlisted)
            }
            Divider()
            Label("New Category…", systemImage: CategorySymbols.add).tag(Self.newTag)
        }
        .labelsHidden()
        .controlSize(compact ? .small : .regular)
        .accessibilityLabel("Category")
        .accessibilityValue(selection)
        .accessibilityIdentifier("category-picker")
    }

    private func track() {
        trackedID = records.first { $0.isLive && WorkCategory.matches($0.name, selection) }?.id ?? trackedID
    }

    private func resolveSelection() {
        let live = records.filter(\.isLive)
        if let trackedID, let record = live.first(where: { $0.id == trackedID }) {
            if record.name != selection { selection = record.name }
        } else if !live.contains(where: { WorkCategory.matches($0.name, selection) }), !keepsUnlisted {
            selection = fallback()
        }
        track()
    }

    private func commit() {
        guard (try? WorkCategory.validate(newName)) != nil else { return }
        do {
            // Saved straight away, so every other picker lists it too.
            selection = try environment.persistence.categoryNamed(newName).name
            isNaming = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancel() {
        isNaming = false
    }
}

enum CategorySymbols {
    static let add = "folder.badge.plus"
    static let deleted = "folder.badge.minus"
    static let move = "arrow.right.circle"
    static let rename = "pencil"
    static let delete = "trash"
    static let actions = "ellipsis.circle"
}

/// A category name with its folder symbol, in secondary text.
struct CategoryLabel: View {
    let name: String
    var font: Font = .caption

    var body: some View {
        Label(name, systemImage: WorkCategory.symbolName)
            .labelStyle(.titleAndIcon)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("Category, \(name)")
    }
}

// MARK: - Categories sheet

/// Creates, renames, moves templates between, and deletes categories.
///
/// Every figure comes from live queries, so the list updates the moment a
/// change is saved anywhere in the app. Work Logs always keep the category they
/// were recorded with.
struct ManageCategoriesSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var records: [WorkCategoryRecord]
    @Query private var templates: [WorkTemplate]
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "completed" }) private var workLogs: [WorkSession]
    @Query(filter: #Predicate<WorkSession> { $0.stateRawValue == "active" || $0.stateRawValue == "paused" }) private var openSessions: [WorkSession]
    let onClose: () -> Void

    private enum Editor: Equatable {
        case adding
        case renaming(UUID)
    }

    @State private var editor: Editor?
    @State private var name = ""
    @State private var fieldError: String?
    @State private var removal: CategoryRemoval?
    @State private var pendingDeletion: CategoryUsage?
    @State private var message: String?
    @FocusState private var fieldIsFocused: Bool

    private var usage: [CategoryUsage] {
        let live = records.filter(\.isLive)
        let order = WorkCategory.sorted(live.map(\.name))
        return CategoryUsage.compute(
            categories: live.sorted { (order.firstIndex(of: $0.name) ?? 0) < (order.firstIndex(of: $1.name) ?? 0) },
            templates: templates, workLogs: workLogs, openSessions: openSessions
        )
    }

    var body: some View {
        let usage = self.usage
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List {
                if editor == .adding {
                    editorRow(prompt: "New category name", actionTitle: "Add", action: add)
                }
                ForEach(usage) { item in
                    if editor == .renaming(item.id) {
                        editorRow(prompt: "Category name", actionTitle: "Rename") { rename(item) }
                    } else {
                        row(item)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 240)
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 440, idealHeight: 560)
        .sheet(item: $removal) { removal in
            CategoryRemovalSheet(removal: removal, destinations: usage.map(\.name).filter { !WorkCategory.matches($0, removal.usage.name) }) { result in
                self.removal = nil
                if let result { message = result }
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { item in
            Button("Delete Category", role: .destructive) { deleteUnused(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(CategoryRemovalText.unusedDeletion(item))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Every template belongs to a category. Renaming or moving a category changes templates and future sessions. Work Logs always keep the category they were recorded with.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                startEditing(.adding, name: "")
            } label: {
                Label("Add Category", systemImage: CategorySymbols.add)
            }
            .disabled(editor == .adding)
            .accessibilityIdentifier("add-category")
        }
        .padding(20)
    }

    private func row(_ item: CategoryUsage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: WorkCategory.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if item.isDefault {
                        Text("Default")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.07), in: .capsule)
                            .help("General can’t be renamed or deleted. Quick tasks start here.")
                    }
                    if item.isUsedByOpenSession {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.green)
                            .help("The session in progress is in this category")
                            .accessibilityLabel("In progress")
                    }
                }
                Text(CategoryRemovalText.usageLine(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.templateNames.joined(separator: ", "))
            }
            Spacer(minLength: 8)
            Menu {
                actions(for: item)
            } label: {
                Image(systemName: CategorySymbols.actions)
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Rename, move templates, or delete")
            .accessibilityLabel("Actions for \(item.name)")
            .accessibilityIdentifier("category-actions-\(item.name)")
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .contextMenu { actions(for: item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(CategoryRemovalText.usageLine(item))")
    }

    @ViewBuilder
    private func actions(for item: CategoryUsage) -> some View {
        Button {
            startEditing(.renaming(item.id), name: item.name)
        } label: {
            Label("Rename…", systemImage: CategorySymbols.rename)
        }
        .disabled(!item.canModify)
        Button {
            removal = CategoryRemoval(usage: item, mode: .migrate)
        } label: {
            Label("Move Templates…", systemImage: CategorySymbols.move)
        }
        .disabled(item.templateCount == 0)
        Divider()
        Button(role: .destructive) {
            requestDelete(item)
        } label: {
            Label("Delete…", systemImage: CategorySymbols.delete)
        }
        .disabled(!item.canModify)
    }

    private func editorRow(prompt: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: WorkCategory.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                TextField(prompt, text: $name, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($fieldIsFocused)
                    .onSubmit(action)
                    .onExitCommand { editor = nil }
                    .onChange(of: name) { fieldError = nil }
                    .accessibilityLabel(prompt)
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled((try? WorkCategory.validate(name)) == nil)
                Button("Cancel") { editor = nil }
            }
            if let fieldError {
                Label(fieldError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            if let message {
                Label(message, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(20)
    }

    // MARK: Actions

    private func startEditing(_ editor: Editor, name: String) {
        self.name = name
        fieldError = nil
        message = nil
        self.editor = editor
        fieldIsFocused = true
    }

    private func add() {
        guard editor == .adding else { return }
        do {
            let record = try environment.persistence.createCategory(named: name)
            message = "Added “\(record.name)”."
            editor = nil
        } catch {
            fieldError = Self.describe(error)
        }
    }

    private func rename(_ item: CategoryUsage) {
        guard editor == .renaming(item.id) else { return }
        do {
            let changed = try environment.persistence.renameCategory(item.name, to: name)
            let target = WorkCategory.normalized(name)
            message = switch changed {
            case 0: "Renamed “\(item.name)” to “\(target)”."
            case 1: "Renamed “\(item.name)” to “\(target)” on 1 template."
            default: "Renamed “\(item.name)” to “\(target)” on \(changed) templates."
            }
            editor = nil
        } catch {
            fieldError = Self.describe(error)
        }
    }

    private func requestDelete(_ item: CategoryUsage) {
        message = nil
        if item.templateCount > 0 {
            removal = CategoryRemoval(usage: item, mode: .delete)
        } else {
            pendingDeletion = item
        }
    }

    private func deleteUnused(_ item: CategoryUsage) {
        pendingDeletion = nil
        do {
            try environment.persistence.deleteCategory(item.name)
            message = "Deleted “\(item.name)”."
        } catch {
            environment.presentedError = PresentableError(error, title: "Couldn’t delete the category")
        }
    }

    static func describe(_ error: Error) -> String {
        let error = error as? LocalizedError
        return [error?.errorDescription, error?.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }
}

/// A category awaiting a move or delete, held by value so the sheet never
/// reads a record that is deleted while it is open.
struct CategoryRemoval: Identifiable, Equatable {
    enum Mode { case migrate, delete }
    let usage: CategoryUsage
    let mode: Mode
    var id: UUID { usage.id }
}

enum CategoryRemovalText {
    static func usageLine(_ item: CategoryUsage) -> String {
        let templates = switch item.templateCount {
        case 0: "Not used by any template"
        case 1...3: "Used by \(item.templateNames.joined(separator: ", "))"
        default: "Used by \(item.templateCount) templates"
        }
        return item.workLogCount == 0 ? templates : "\(templates) · \(workLogs(item.workLogCount))"
    }

    static func workLogs(_ count: Int) -> String { count == 1 ? "1 work log" : "\(count) work logs" }
    static func templates(_ count: Int) -> String { count == 1 ? "1 template" : "\(count) templates" }

    static func history(_ item: CategoryUsage) -> String {
        item.workLogCount == 0
            ? "No work logs are recorded in “\(item.name)”."
            : "\(workLogs(item.workLogCount).capitalizedFirst) recorded in “\(item.name)” keep that category in Work Logs, Analytics, and exports. They aren’t rewritten."
    }

    static func unusedDeletion(_ item: CategoryUsage) -> String {
        var parts = ["No template uses this category."]
        if item.workLogCount > 0 { parts.append(history(item)) }
        if item.isUsedByOpenSession { parts.append("The session in progress keeps “\(item.name)”.") }
        parts.append("This can’t be undone.")
        return parts.joined(separator: " ")
    }
}

/// Moves a category's templates to another category, optionally deleting it.
struct CategoryRemovalSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let removal: CategoryRemoval
    let destinations: [String]
    /// Called with a confirmation message after success, or `nil` on Cancel.
    let onFinish: (String?) -> Void

    @State private var destination = WorkCategory.defaultName
    @State private var errorMessage: String?
    @State private var isWorking = false

    private var item: CategoryUsage { removal.usage }
    private var deletes: Bool { removal.mode == .delete }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: deletes ? CategorySymbols.deleted : CategorySymbols.move)
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(deletes ? "Delete “\(item.name)”?" : "Move Templates from “\(item.name)”")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(deletes
                         ? "“\(item.name)” is used by \(CategoryRemovalText.templates(item.templateCount)). Choose a category for them; they move there before “\(item.name)” is deleted."
                         : "Choose a category for the \(CategoryRemovalText.templates(item.templateCount)) in “\(item.name)”. The category itself stays.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Templates").foregroundStyle(.secondary)
                        Text(item.templateNames.joined(separator: ", "))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GridRow {
                        Text("Work Logs").foregroundStyle(.secondary)
                        Text(item.workLogCount == 0 ? "None" : "\(item.workLogCount), kept in “\(item.name)”")
                    }
                    if item.isUsedByOpenSession {
                        GridRow {
                            Text("In Progress").foregroundStyle(.secondary)
                            Text("Keeps “\(item.name)” until it finishes")
                        }
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LabeledContent("Move templates to") {
                Picker("Move templates to", selection: $destination) {
                    ForEach(destinations, id: \.self) { name in
                        Label(name, systemImage: WorkCategory.symbolName).tag(name)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("category-destination")
            }

            VStack(alignment: .leading, spacing: 6) {
                note("clock.arrow.circlepath", CategoryRemovalText.history(item))
                note("arrow.forward", "New sessions from these templates start in “\(destination)”.")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                if deletes {
                    Button("Move and Delete", role: .destructive, action: perform)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || destinations.isEmpty)
                } else {
                    Button("Move Templates", action: perform)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || destinations.isEmpty)
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if !destinations.contains(destination) { destination = destinations.first ?? WorkCategory.defaultName }
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func perform() {
        // One save, guarded against a second click while it runs.
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if deletes {
                let moved = try environment.persistence.deleteCategory(item.name, migratingTemplatesTo: destination)
                onFinish("Moved \(CategoryRemovalText.templates(moved)) to “\(destination)” and deleted “\(item.name)”.")
            } else {
                let moved = try environment.persistence.migrateCategory(item.name, to: destination)
                onFinish("Moved \(CategoryRemovalText.templates(moved)) from “\(item.name)” to “\(destination)”.")
            }
        } catch {
            errorMessage = ManageCategoriesSheet.describe(error)
        }
    }
}
