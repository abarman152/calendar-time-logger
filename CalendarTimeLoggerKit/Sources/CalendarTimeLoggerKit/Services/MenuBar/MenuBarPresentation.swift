import Foundation

/// One styled piece of the menu bar item.
public struct MenuBarSegment: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case icon, name, separator, duration, pausedIndicator
    }

    public let kind: Kind
    /// Text for text segments; the SF Symbol name for `icon` and `pausedIndicator`.
    public let text: String
    /// `nil` renders in the menu bar's own text color.
    public let color: HexColor?

    public init(kind: Kind, text: String, color: HexColor? = nil) {
        self.kind = kind
        self.text = text
        self.color = color
    }

    /// Whether `text` is an SF Symbol name rather than displayable text.
    public var isSymbol: Bool { kind == .icon || kind == .pausedIndicator }
}

/// The information needed to present a session in the menu bar.
public struct MenuBarSessionSnapshot: Hashable, Sendable {
    public var templateName: String
    /// SF Symbol name.
    public var templateIcon: String
    public var state: SessionState
    public var activeDuration: TimeInterval
    public var configuration: MenuBarConfiguration

    public init(templateName: String, templateIcon: String, state: SessionState, activeDuration: TimeInterval, configuration: MenuBarConfiguration) {
        self.templateName = templateName
        self.templateIcon = templateIcon
        self.state = state
        self.activeDuration = activeDuration
        self.configuration = configuration
    }
}

/// How the permanent Calendar Time Logger item looks when no session is shown.
public enum MenuBarIdentityStyle: String, CaseIterable, Identifiable, Sendable {
    /// The CTL mark: white “CTL” on a black rounded plate, as in the app logo.
    case mark
    /// “CTL” in a rounded outline that macOS tints for the menu bar.
    case badge
    /// “CTL” as plain menu bar text.
    case text
    /// A clock symbol.
    case symbol

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mark: "CTL Mark"
        case .badge: "CTL Outline"
        case .text: "CTL Text"
        case .symbol: "Clock Symbol"
        }
    }
}

/// The app's identity in the menu bar.
public enum MenuBarIdentity {
    public static let title = "CTL"
    public static let symbolName = "clock"
    public static let accessibilityLabel = "Calendar Time Logger, not working"
}

/// What the menu bar item shows.
public struct MenuBarPresentation: Hashable, Sendable {
    public enum Symbol: String, Sendable {
        /// A session runs but its template hides identity in the menu bar.
        case running = "timer"
        case paused = "pause.circle"
    }

    /// `true` when the item shows the Calendar Time Logger (CTL) identity,
    /// which is whenever no session is open.
    public let showsIdentity: Bool
    /// Styled segments. Empty when `showsIdentity` or `symbol` applies.
    public let segments: [MenuBarSegment]
    public let symbol: Symbol?
    /// Fill of the pill behind the segments, if the template sets one.
    public let backgroundColor: HexColor?
    public let accessibilityLabel: String

    /// The readable text of the item (symbols omitted).
    public var plainText: String {
        segments.filter { !$0.isSymbol }.map(\.text).joined().trimmingCharacters(in: .whitespaces)
    }

    public var iconSymbolName: String? { segments.first { $0.kind == .icon }?.text }

    public var usesCustomColors: Bool { backgroundColor != nil || segments.contains { $0.color != nil } }
}

public enum MenuBarFormatter {
    public static func presentation(for snapshot: MenuBarSessionSnapshot?, showsSeconds: Bool) -> MenuBarPresentation {
        guard let snapshot, snapshot.state.isOpen else {
            return MenuBarPresentation(showsIdentity: true, segments: [], symbol: nil, backgroundColor: nil,
                                       accessibilityLabel: MenuBarIdentity.accessibilityLabel)
        }

        let config = snapshot.configuration
        let isPaused = snapshot.state == .paused
        let duration = DurationFormatting.clock(snapshot.activeDuration, showsSeconds: showsSeconds)
        let spokenState = isPaused ? "paused" : "working"
        let accessibility = "Calendar Time Logger, \(spokenState) on \(snapshot.templateName), "
            + DurationFormatting.spoken(snapshot.activeDuration)

        guard config.isVisible else {
            return MenuBarPresentation(showsIdentity: false, segments: [], symbol: isPaused ? .paused : .running,
                                       backgroundColor: nil, accessibilityLabel: accessibility)
        }

        // On a colored pill, automatic foregrounds use a contrasting color so the
        // item stays legible; without a pill they follow the menu bar.
        let background = config.backgroundColor
        func color(_ custom: HexColor?) -> HexColor? { custom ?? background?.contrastingForeground }

        let mode = config.displayMode
        var segments: [MenuBarSegment] = []
        // Paused state is shown with a symbol, not just color.
        if isPaused {
            segments.append(MenuBarSegment(kind: .pausedIndicator, text: "pause.fill", color: color(nil)))
        }
        let showsIcon = mode.requiresIcon || (mode == .nameOnly && config.showsIconWithName)
        let icon = TemplateSymbol.displayName(snapshot.templateIcon)
        if showsIcon {
            segments.append(MenuBarSegment(kind: .icon, text: icon, color: color(config.iconColor)))
        }
        if mode.showsName {
            if showsIcon { segments.append(MenuBarSegment(kind: .separator, text: " ", color: color(nil))) }
            segments.append(MenuBarSegment(kind: .name, text: snapshot.templateName, color: color(config.nameColor)))
        }
        if mode.showsDuration {
            if mode.showsName {
                segments.append(MenuBarSegment(kind: .separator, text: config.separator, color: color(nil)))
            } else if showsIcon {
                segments.append(MenuBarSegment(kind: .separator, text: " ", color: color(nil)))
            }
            segments.append(MenuBarSegment(kind: .duration, text: duration, color: color(config.durationColor)))
        }

        return MenuBarPresentation(showsIdentity: false, segments: segments, symbol: nil,
                                   backgroundColor: background, accessibilityLabel: accessibility)
    }
}
