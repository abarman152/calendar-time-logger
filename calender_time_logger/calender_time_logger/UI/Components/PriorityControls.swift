import CalendarTimeLoggerKit
import SwiftUI

/// Icons and tints for task priority. Identity is always carried by the symbol
/// and the label together, never by color alone.
enum PrioritySymbols {
    static let urgent = "exclamationmark.circle"
    static let important = "star"
    /// Drawn when a flag is set, so Yes reads differently from No by shape as
    /// well as by color.
    static let urgentFilled = "exclamationmark.circle.fill"
    static let importantFilled = "star.fill"
    static let section = "flag"
    static let quickTask = "bolt"
    static let quadrants = "square.split.2x2"

    static let urgentTint = Color.orange
    static let importantTint = Color.accentColor
}

/// The mandatory Urgent and Important choice, as two native segmented controls.
///
/// Both always hold a value, so there is no unset state to validate.
struct TaskPriorityPicker: View {
    @Binding var priority: TaskPriority
    var labelWidth: CGFloat = 92
    /// Stacks the rows tightly for the menu bar popover.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            row("Urgent", symbol: PrioritySymbols.urgent, isOn: $priority.isUrgent)
            row("Important", symbol: PrioritySymbols.important, isOn: $priority.isImportant)
        }
    }

    private func row(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        let value = isOn.wrappedValue
        let tint = title == "Urgent" ? PrioritySymbols.urgentTint : PrioritySymbols.importantTint
        return HStack(spacing: 10) {
            Label {
                Text(title)
                    .fontWeight(value ? .semibold : .regular)
            } icon: {
                // Filled and tinted for Yes, an outline for No: the state is
                // readable at a glance without looking at the segment.
                Image(systemName: value ? filled(symbol) : symbol)
                    .foregroundStyle(value ? tint : Color.secondary)
            }
            .labelStyle(.titleAndIcon)
            .font(compact ? .callout : .body)
            // Never wraps: the menu bar popover is narrow, and “Important”
            // split across two lines misaligns the rows.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: labelWidth, alignment: .leading)
            .accessibilityHidden(true)
            Picker(title, selection: isOn) {
                Text("No").tag(false)
                Text("Yes").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: compact ? 120 : 160)
            .accessibilityLabel(title)
            .accessibilityValue(TaskPriority.yesNo(value))
            .accessibilityIdentifier("priority-\(title.lowercased())")
        }
    }

    private func filled(_ symbol: String) -> String {
        symbol == PrioritySymbols.urgent ? PrioritySymbols.urgentFilled : PrioritySymbols.importantFilled
    }
}

/// Compact chips for the flags that are set. Nothing is drawn when a session is
/// neither urgent nor important, unless `showsNeither` asks for it.
struct PriorityChips: View {
    let priority: TaskPriority
    var showsNeither = false
    var size: ChipSize = .regular

    enum ChipSize {
        case regular, small
        var font: Font { self == .small ? .caption2.weight(.semibold) : .caption.weight(.semibold) }
        var horizontalPadding: CGFloat { self == .small ? 6 : 7 }
    }

    var body: some View {
        if priority.isUrgent || priority.isImportant {
            HStack(spacing: 4) {
                if priority.isUrgent {
                    chip("Urgent", symbol: PrioritySymbols.urgentFilled, tint: PrioritySymbols.urgentTint)
                }
                if priority.isImportant {
                    chip("Important", symbol: PrioritySymbols.importantFilled, tint: PrioritySymbols.importantTint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(priority.accessibilityLabel)
        } else if showsNeither {
            chip("Neither", symbol: "circle", tint: .secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(priority.accessibilityLabel)
        }
    }

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.backgroundProminence) private var prominence

    private func chip(_ title: String, symbol: String, tint: Color) -> some View {
        let tint = prominence == .increased ? Color.white : tint
        return chipBody(title, symbol: symbol, tint: tint)
    }

    private func chipBody(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(size.font)
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, 2)
        .background(tint.opacity(0.16), in: .capsule)
        .overlay {
            Capsule().strokeBorder(tint.opacity(contrast == .increased ? 0.8 : 0.35), lineWidth: 0.5)
        }
    }
}

/// Symbols only, for narrow rows such as the template sidebar. Nothing is drawn
/// when neither flag is set.
struct PriorityMarkers: View {
    let priority: TaskPriority
    var size: CGFloat = 11
    /// Selected list rows draw on the accent color, where an accent-tinted
    /// symbol would disappear.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        if priority.isUrgent || priority.isImportant {
            let onAccent = prominence == .increased
            HStack(spacing: 3) {
                if priority.isUrgent {
                    Image(systemName: PrioritySymbols.urgentFilled)
                        .foregroundStyle(onAccent ? Color.white : PrioritySymbols.urgentTint)
                }
                if priority.isImportant {
                    Image(systemName: PrioritySymbols.importantFilled)
                        .foregroundStyle(onAccent ? Color.white : PrioritySymbols.importantTint)
                }
            }
            .font(.system(size: size, weight: .semibold))
            .help(priority.quadrant.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(priority.accessibilityLabel)
        }
    }
}

/// The combination stated in full, for headers and analytics cards.
struct PriorityQuadrantLabel: View {
    let quadrant: TaskPriorityQuadrant
    var usesShortTitle = false

    var body: some View {
        Label {
            Text(usesShortTitle ? quadrant.shortTitle : quadrant.title)
        } icon: {
            Image(systemName: quadrant.symbolName)
                .foregroundStyle(quadrant.color.color)
        }
        .accessibilityLabel(quadrant.title)
    }
}

/// Two rows of Yes / No, for detail panes and confirmations.
struct PriorityValueRows: View {
    let priority: TaskPriority
    var labelWidth: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Urgent", symbol: PrioritySymbols.urgent, value: priority.isUrgent, tint: PrioritySymbols.urgentTint)
            row("Important", symbol: PrioritySymbols.important, value: priority.isImportant, tint: PrioritySymbols.importantTint)
        }
    }

    private func row(_ title: String, symbol: String, value: Bool, tint: Color) -> some View {
        // The label keeps a minimum width so the two rows line up, but neither
        // text wraps when the inspector is narrow.
        HStack(spacing: 8) {
            Image(systemName: value ? (symbol == PrioritySymbols.urgent ? PrioritySymbols.urgentFilled : PrioritySymbols.importantFilled) : symbol)
                .foregroundStyle(value ? tint : Color.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: labelWidth, alignment: .leading)
            Spacer(minLength: 6)
            Text(TaskPriority.yesNo(value))
                .fontWeight(value ? .semibold : .regular)
                .foregroundStyle(value ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(TaskPriority.yesNo(value))")
    }
}

/// A card section for the template editor and the start sheets.
struct TaskPriorityCard: View {
    @Binding var priority: TaskPriority
    var subtitle: String?
    var footnote: String?

    var body: some View {
        SectionCard("Task Priority", symbol: PrioritySymbols.section) {
            PriorityChips(priority: priority, showsNeither: true, size: .small)
        } content: {
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TaskPriorityPicker(priority: $priority)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
