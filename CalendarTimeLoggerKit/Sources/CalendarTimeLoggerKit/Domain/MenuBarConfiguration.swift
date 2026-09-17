import Foundation

/// How a template identifies itself in the menu bar while a session runs.
public enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case iconOnly
    case nameOnly
    case durationOnly
    case iconAndDuration
    case nameAndDuration
    case iconNameAndDuration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iconOnly: "Icon Only"
        case .nameOnly: "Name Only"
        case .durationOnly: "Duration Only"
        case .iconAndDuration: "Icon + Duration"
        case .nameAndDuration: "Name + Duration"
        case .iconNameAndDuration: "Icon + Name + Duration"
        }
    }

    public var showsName: Bool { self == .nameAndDuration || self == .nameOnly || self == .iconNameAndDuration }
    public var showsDuration: Bool {
        self == .nameAndDuration || self == .durationOnly || self == .iconAndDuration || self == .iconNameAndDuration
    }
    /// Whether the icon is always part of this mode (Name Only makes it optional).
    public var requiresIcon: Bool { self == .iconAndDuration || self == .iconOnly || self == .iconNameAndDuration }
}

/// Per-template menu bar presentation. `nil` colors mean “automatic”: without a
/// background the item matches the menu bar in light and dark appearance; on a
/// background, automatic foregrounds use a contrasting color.
public struct MenuBarConfiguration: Codable, Hashable, Sendable {
    public var isVisible: Bool
    public var displayMode: MenuBarDisplayMode
    /// Whether Name Only also shows the icon.
    public var showsIconWithName: Bool
    public var separator: String
    public var iconColor: HexColor?
    public var nameColor: HexColor?
    public var durationColor: HexColor?
    /// Fill of the rounded pill drawn behind the item. `nil` draws no pill.
    public var backgroundColor: HexColor?

    public static let defaultSeparator = " · "
    /// Stored format version. 1.0 configurations have no version key.
    static let currentVersion = 2

    public init(
        isVisible: Bool = true,
        displayMode: MenuBarDisplayMode = .iconNameAndDuration,
        showsIconWithName: Bool = true,
        separator: String = MenuBarConfiguration.defaultSeparator,
        iconColor: HexColor? = nil,
        nameColor: HexColor? = nil,
        durationColor: HexColor? = nil,
        backgroundColor: HexColor? = nil
    ) {
        self.isVisible = isVisible
        self.displayMode = displayMode
        self.showsIconWithName = showsIconWithName
        self.separator = separator
        self.iconColor = iconColor
        self.nameColor = nameColor
        self.durationColor = durationColor
        self.backgroundColor = backgroundColor
    }

    public static let `default` = MenuBarConfiguration()

    public var usesCustomColors: Bool {
        iconColor != nil || nameColor != nil || durationColor != nil || backgroundColor != nil
    }

    private enum CodingKeys: String, CodingKey {
        case version, isVisible, displayMode, showsIconWithName, separator, iconColor, nameColor, durationColor, backgroundColor
    }

    // Tolerant decoding keeps older stored configurations readable when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MenuBarConfiguration.default
        let version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? fallback.isVisible
        let storedMode = try? c.decodeIfPresent(MenuBarDisplayMode.self, forKey: .displayMode)
        showsIconWithName = try c.decodeIfPresent(Bool.self, forKey: .showsIconWithName) ?? fallback.showsIconWithName
        separator = try c.decodeIfPresent(String.self, forKey: .separator) ?? fallback.separator
        iconColor = try? c.decodeIfPresent(HexColor.self, forKey: .iconColor)
        nameColor = try? c.decodeIfPresent(HexColor.self, forKey: .nameColor)
        durationColor = try? c.decodeIfPresent(HexColor.self, forKey: .durationColor)
        backgroundColor = try? c.decodeIfPresent(HexColor.self, forKey: .backgroundColor)

        if version < 2 {
            // In 1.0, Name + Duration was the default and showed the icon unless
            // “Show icon with name” was off. That appearance is now its own mode.
            let legacyMode = storedMode ?? .nameAndDuration
            displayMode = legacyMode == .nameAndDuration && showsIconWithName ? .iconNameAndDuration : legacyMode
        } else {
            displayMode = storedMode ?? fallback.displayMode
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(displayMode, forKey: .displayMode)
        try c.encode(showsIconWithName, forKey: .showsIconWithName)
        try c.encode(separator, forKey: .separator)
        try c.encodeIfPresent(iconColor, forKey: .iconColor)
        try c.encodeIfPresent(nameColor, forKey: .nameColor)
        try c.encodeIfPresent(durationColor, forKey: .durationColor)
        try c.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
    }
}

extension HexColor {
    /// WCAG relative luminance (0 black – 1 white).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two colors (1–21).
    public func contrastRatio(with other: HexColor) -> Double {
        let (l1, l2) = (relativeLuminance, other.relativeLuminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public static let white = HexColor(red: 1, green: 1, blue: 1)
    public static let black = HexColor(red: 0, green: 0, blue: 0)

    /// Foreground for text on this color. White is preferred, as on macOS
    /// tinted controls, whenever it meets the WCAG 3:1 minimum for UI
    /// components; otherwise whichever of white or black contrasts more.
    public var contrastingForeground: HexColor {
        if contrastRatio(with: .white) >= 3 { return .white }
        return contrastRatio(with: .white) >= contrastRatio(with: .black) ? .white : .black
    }
}
