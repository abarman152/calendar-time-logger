import CalendarTimeLoggerKit
import SwiftUI

/// The template icon control: the current symbol, a row of related symbols
/// for quick changes, and a button that opens the full searchable picker.
struct SymbolPickerField: View {
    @Binding var symbol: String
    let color: HexColor
    @State private var showsPicker = false

    var body: some View {
        // Wraps in a narrow editor instead of pushing the card past its edge.
        ChipFlowLayout(spacing: 6) {
            ForEach(quickSymbols, id: \.self) { name in
                SymbolCell(name: name, isSelected: name == symbol, size: 30) { symbol = name }
            }
            Button {
                showsPicker = true
            } label: {
                Label("More Icons", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 7))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Choose from all icons")
            .accessibilityLabel("More icons")
            .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
                SymbolPickerView(selection: $symbol, color: color) { showsPicker = false }
            }
        }
    }

    /// The selected symbol followed by others from its category.
    private var quickSymbols: [String] {
        let selected = TemplateSymbol.displayName(symbol)
        let category = SymbolCatalog.categories.first { $0.symbols.contains { $0.name == selected } } ?? SymbolCatalog.categories[0]
        let others = category.symbols.map(\.name).filter { $0 != selected }
        return Array(([selected] + others).prefix(8))
    }
}

/// A large, searchable grid of SF Symbols grouped by category.
struct SymbolPickerView: View {
    @Binding var selection: String
    let color: HexColor
    var onChoose: () -> Void = {}

    @State private var query = ""
    @State private var categoryID: String?
    @FocusState private var searchFocused: Bool

    private static let cell: CGFloat = 38
    private static let spacing: CGFloat = 6
    private static let columnCount = 10
    private let columns = Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.spacing), count: Self.columnCount)
    /// Wide enough for every column, the grid's padding, and a legacy scroller,
    /// so the last column is never covered or clipped.
    private static var gridWidth: CGFloat {
        CGFloat(columnCount) * cell + CGFloat(columnCount - 1) * spacing + 4 + 16
    }

    var body: some View {
        let results = SymbolCatalog.search(query, categoryID: categoryID)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TemplateIconView(icon: selection, color: color, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Choose an Icon").font(.headline)
                    Text(SymbolPickerView.readableName(TemplateSymbol.displayName(selection)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search icons", text: $query, prompt: Text("Search icons"))
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                // Return picks the first match.
                .onSubmit { if let first = results.first { choose(first) } }
                .accessibilityLabel("Search icons")

            // Wraps instead of scrolling sideways, so every category is visible.
            ChipFlowLayout(spacing: 6) {
                CategoryChip(title: "All", isSelected: categoryID == nil) { categoryID = nil }
                ForEach(SymbolCatalog.categories) { category in
                    CategoryChip(title: category.title, isSelected: categoryID == category.id) { categoryID = category.id }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        LazyVGrid(columns: columns, spacing: Self.spacing) {
                            ForEach(results, id: \.self) { name in
                                SymbolCell(name: name, isSelected: name == selection, size: Self.cell) {
                                    choose(name)
                                }
                                .id(name)
                            }
                        }
                        .padding(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 260)
                .onAppear {
                    // Opens on the current icon rather than the top of the list.
                    let current = TemplateSymbol.displayName(selection)
                    if results.contains(current) { proxy.scrollTo(current, anchor: .center) }
                }
            }

            Text("\(results.count) \(results.count == 1 ? "icon" : "icons")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(width: Self.gridWidth + 28)
        .onAppear { searchFocused = true }
    }

    private func choose(_ name: String) {
        selection = name
        onChoose()
    }

    /// `chevron.left.forwardslash.chevron.right` → “Chevron left forwardslash chevron right”.
    static func readableName(_ name: String) -> String {
        let words = name.split(separator: ".").joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

private struct SymbolCell: View {
    let name: String
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size * 0.46))
                .frame(width: size, height: size)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.12 : 0.05)))
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(SymbolPickerView.readableName(name))
        .accessibilityLabel(SymbolPickerView.readableName(name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(title) icons")
    }
}
