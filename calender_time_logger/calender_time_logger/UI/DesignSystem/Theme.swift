import AppKit
import CalendarTimeLoggerKit
import SwiftUI

extension HexColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    init?(_ color: Color) {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent)
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension AccentPreference {
    /// `nil` uses the app accent (the purple `AccentColor` asset), which macOS
    /// replaces with the user's system accent unless it is set to Multicolor.
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
}

extension LayoutDensity {
    var rowPadding: CGFloat { self == .compact ? 2 : 6 }
    var sectionSpacing: CGFloat { self == .compact ? 14 : 20 }
}

enum Metrics {
    /// One corner radius for cards, one for controls inside them.
    static let cardCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 8
    static let contentMaxWidth: CGFloat = 1120
    static let cardPadding: CGFloat = 18
}

/// A rounded card surface that adapts to light and dark appearance and to
/// Increase Contrast.
struct CardBackground: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: .rect(cornerRadius: Metrics.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08), lineWidth: contrast == .increased ? 1 : 0.5)
            }
    }
}

extension View {
    func card(padding: CGFloat = Metrics.cardPadding) -> some View { modifier(CardBackground(padding: padding)) }
}

/// A card with a headline and optional trailing accessory.
struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String? = nil, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// A row inside a grouped card: label on the left, value on the right,
/// separated by hairlines like a grouped Form.
struct CardRow<Value: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// Applies the user's appearance and accent preferences to a scene's root view.
struct AppearanceModifier: ViewModifier {
    let settings: SettingsStore

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
    }
}

extension View {
    func appAppearance(_ settings: SettingsStore) -> some View { modifier(AppearanceModifier(settings: settings)) }
}

enum Greeting {
    static func text(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good Morning"
        case 12..<17: "Good Afternoon"
        default: "Good Evening"
        }
    }

    static func subtitle(for date: Date, calendar: Calendar = .current) -> String {
        let messages = [
            "Stay consistent. Small steps add up to big results.",
            "Stay focused. Consistent progress leads to meaningful results.",
            "One session at a time."
        ]
        return messages[calendar.ordinality(of: .day, in: .year, for: date).map { $0 % messages.count } ?? 0]
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

enum DayTitle {
    static func text(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

/// A button style for full-width tile buttons (quick actions, template cards).
struct TileButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        TileButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct TileButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            configuration.label
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius)
                        .fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.09 : 0.05)))
                        .brightness(prominent && (isHovering || configuration.isPressed) ? 0.06 : 0)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius)
                        .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : (prominent ? 0 : 0.08)), lineWidth: 0.5)
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(.rect(cornerRadius: Metrics.controlCornerRadius))
                .onHover { isHovering = $0 }
        }
    }
}
