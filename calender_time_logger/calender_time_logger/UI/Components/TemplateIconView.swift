import CalendarTimeLoggerKit
import SwiftUI

/// A template's SF Symbol on a rounded tile in the template color. Identity is
/// always carried by the symbol and the accompanying name, never by color alone.
struct TemplateIconView: View {
    /// SF Symbol name. Legacy or unknown values fall back to a catalog symbol.
    let icon: String
    let color: HexColor
    var size: CGFloat = 32
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: TemplateSymbol.displayName(icon))
            .font(.system(size: size * 0.46, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color.contrastingForeground.color)
            .frame(width: size, height: size)
            .background(color.color.gradient, in: .rect(cornerRadius: size * 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : 0.1), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Icon plus name, used in rows and headers.
struct TemplateLabel: View {
    let name: String
    let icon: String
    let color: HexColor
    var iconSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            TemplateIconView(icon: icon, color: color, size: iconSize)
            Text(name)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

/// Calendar sync state shown with a symbol and text.
struct SyncStatusLabel: View {
    let status: CalendarSyncStatus
    var compact = false

    var body: some View {
        Group {
            if compact {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .help(status.displayName)
            } else {
                Label(status.displayName, systemImage: symbol)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityLabel("Calendar: \(status.displayName)")
    }

    private var symbol: String {
        switch status {
        case .notSynced: "calendar"
        case .synced: "calendar.badge.checkmark"
        case .failed: "exclamationmark.triangle"
        case .eventMissing: "calendar.badge.exclamationmark"
        }
    }

    private var tint: Color {
        switch status {
        case .notSynced: .secondary
        case .synced: .green
        case .failed: .orange
        case .eventMissing: .orange
        }
    }
}

/// A row of tag chips.
struct TagChips: View {
    let tags: [String]
    /// Wraps chips onto more lines instead of laying them out in one row.
    /// Used where every tag is shown in a narrow column.
    var wraps = false

    var body: some View {
        if !tags.isEmpty {
            Group {
                if wraps {
                    ChipFlowLayout(spacing: 4) { chips }
                } else {
                    HStack(spacing: 4) { chips }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }

    private var chips: some View {
        ForEach(tags, id: \.self) { tag in
            // A chip never breaks inside a tag; it truncates when it can't fit at all.
            Text("#\(tag)")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: .capsule)
        }
    }
}

/// Lays chips out left to right, starting a new line when the next one
/// doesn't fit the proposed width.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = row.sizes[index - row.indices.lowerBound]
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: Range<Int>
        var sizes: [CGSize]
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(_ subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(indices: 0..<0, sizes: [], width: 0, height: 0)
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            let proposedWidth = current.sizes.isEmpty ? size.width : current.width + spacing + size.width
            if !current.sizes.isEmpty, proposedWidth > maxWidth {
                rows.append(current)
                current = Row(indices: index..<index, sizes: [], width: 0, height: 0)
            }
            current.width = current.sizes.isEmpty ? size.width : current.width + spacing + size.width
            current.sizes.append(size)
            current.indices = current.indices.lowerBound..<(index + 1)
            current.height = max(current.height, size.height)
        }
        if !current.sizes.isEmpty { rows.append(current) }
        return rows
    }
}

/// A single labelled statistic.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// A capsule stating the session state in words, with a symbol.
struct SessionStateBadge: View {
    let state: SessionState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .accessibilityHidden(true)
            Text(state.displayName)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.16), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(state.displayName)")
    }

    private var symbol: String {
        switch state {
        case .paused: "pause.fill"
        case .completed: "checkmark"
        case .cancelled: "xmark"
        default: "circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .paused: .orange
        case .completed: .blue
        case .cancelled: .secondary
        default: .green
        }
    }
}
