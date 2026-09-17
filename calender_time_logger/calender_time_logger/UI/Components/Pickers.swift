import CalendarTimeLoggerKit
import SwiftUI

/// Chooses a calendar, grouped by account. `nil` selects the fallback option.
struct CalendarPicker: View {
    let title: String
    @Binding var selection: String?
    let calendars: [CalendarInfo]
    let fallbackTitle: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text(fallbackTitle).tag(String?.none)
            if let selection, !calendars.contains(where: { $0.id == selection }) {
                Text("Unavailable Calendar").tag(String?.some(selection))
            }
            ForEach(groupedSources, id: \.self) { source in
                Section(source) {
                    ForEach(calendars.filter { $0.sourceTitle == source }) { calendar in
                        Label {
                            Text(calendar.title)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(calendar.color?.color ?? .secondary)
                        }
                        .tag(String?.some(calendar.id))
                    }
                }
            }
        }
    }

    private var groupedSources: [String] {
        var seen = Set<String>()
        return calendars.map(\.sourceTitle).filter { seen.insert($0).inserted }
    }
}

struct Swatch: View {
    let color: HexColor
    let name: String
    let isSelected: Bool
    var size: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.color)
                .frame(width: size, height: size)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.45, weight: .bold))
                            .foregroundStyle(color.contrastingForeground.color)
                    }
                }
                .overlay(Circle().strokeBorder(.primary.opacity(isSelected ? 0.6 : 0.15), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

