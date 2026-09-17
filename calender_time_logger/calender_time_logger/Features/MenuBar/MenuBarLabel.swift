import AppKit
import CalendarTimeLoggerKit
import SwiftUI

/// The permanent Calendar Time Logger menu bar item.
///
/// - No open session: the CTL identity (badge, text, or clock symbol, per Settings).
/// - Open session: the running template, styled by its menu bar configuration.
///
/// Automatic colors render as template content, which macOS tints for light,
/// dark, and highlighted menu bars. Custom colors or a background pill render
/// into a non-template image so the colors survive. Only the item's own
/// content is drawn; the system menu bar background is never changed.
struct MenuBarLabel: View {
    let environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let presentation = environment.menuBar.presentation(for: environment.sessions.activeSession, now: environment.clock.now)

        Group {
            if presentation.showsIdentity {
                identity(environment.settings.menuBarIdentityStyle)
            } else if let symbol = presentation.symbol {
                Image(systemName: symbol.rawValue)
            } else if let image = Self.renderImage(presentation, colorScheme: colorScheme) {
                Image(nsImage: image)
            } else {
                Text(presentation.plainText)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(presentation.accessibilityLabel)
        // The label exists from launch, so it also presents the main window when
        // Settings asks for it, even if window restoration remembered it closed.
        .task { await LaunchWindowPresenter.presentIfNeeded(environment: environment, openWindow: openWindow) }
    }

    @ViewBuilder
    private func identity(_ style: MenuBarIdentityStyle) -> some View {
        switch style {
        case .mark:
            if let image = Self.identityMarkImage(colorScheme: colorScheme) {
                Image(nsImage: image)
            } else {
                Text(MenuBarIdentity.title)
            }
        case .badge:
            if let image = Self.identityBadgeImage() {
                Image(nsImage: image)
            } else {
                Text(MenuBarIdentity.title)
            }
        case .text:
            Text(MenuBarIdentity.title)
                .font(.system(size: 13, weight: .semibold))
        case .symbol:
            Image(systemName: MenuBarIdentity.symbolName)
        }
    }

    /// The CTL mark: the original white “CTL” wordmark, centered on a black
    /// rounded plate, as in the app icon.
    ///
    /// The glyphs are the `CTLWordmark` image, lifted from the original logo by
    /// `scripts/generate-app-icon.swift` and only ever scaled down, so the menu
    /// bar shows the same letterforms as the icon. The plate keeps its colors,
    /// so this is a non-template image. On a dark menu bar a hairline keeps the
    /// black plate defined against the background; on a light one the plate
    /// stands on its own.
    static func identityMarkImage(colorScheme: ColorScheme) -> NSImage? {
        let mark = Image("CTLWordmark")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: 23, height: 10)
            .frame(width: 30, height: 16)
            .background(.black, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.55 : 0), lineWidth: 0.5)
            }
            .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: mark)
        renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        image.accessibilityDescription = MenuBarIdentity.accessibilityLabel
        return image
    }

    /// The CTL outline: “CTL” in an outlined rounded square, followed by a
    /// small chevron that signals the menu. It is a template image, so macOS
    /// colors it for light, dark, and highlighted menu bars. Strokes use
    /// whole-pixel widths at 2x for a sharp edge.
    static func identityBadgeImage() -> NSImage? {
        let badge = HStack(spacing: 3) {
            Text(MenuBarIdentity.title)
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(.black)
                .frame(width: 31, height: 17)
                .overlay {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .strokeBorder(.black, lineWidth: 1.5)
                }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 1)

        let renderer = ImageRenderer(content: badge)
        renderer.scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = MenuBarIdentity.accessibilityLabel
        return image
    }

    /// Renders the session segments. Returns `nil` when plain text suffices
    /// (automatic colors, no symbols, no pill).
    static func renderImage(_ presentation: MenuBarPresentation, colorScheme: ColorScheme) -> NSImage? {
        let hasSymbols = presentation.segments.contains(where: \.isSymbol)
        guard presentation.usesCustomColors || hasSymbols else { return nil }
        let content = MenuBarSegmentsView(segments: presentation.segments, backgroundColor: presentation.backgroundColor)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Fully automatic content is a template so macOS tints it natively.
        image.isTemplate = !presentation.usesCustomColors
        image.accessibilityDescription = presentation.accessibilityLabel
        return image
    }
}

/// Styled menu bar segments, also used for previews in the template editor.
struct MenuBarSegmentsView: View {
    let segments: [MenuBarSegment]
    var backgroundColor: HexColor?
    var fontSize: CGFloat = 13
    /// In-app previews set this so a long template name truncates in the
    /// middle instead of widening the preview past its container. The menu bar
    /// item itself keeps its full, fixed size.
    var truncatesName = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                piece(segment)
            }
        }
        .font(.system(size: fontSize, weight: backgroundColor == nil ? .regular : .medium))
        .monospacedDigit()
        .padding(.horizontal, backgroundColor == nil ? 0 : 7)
        .frame(height: backgroundColor == nil ? nil : fontSize + 5)
        .background {
            if let backgroundColor {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor.color)
            }
        }
        .fixedSize(horizontal: !truncatesName, vertical: true)
    }

    @ViewBuilder
    private func piece(_ segment: MenuBarSegment) -> some View {
        let style = segment.color?.color ?? .primary
        if segment.isSymbol {
            Image(systemName: segment.text)
                .font(.system(size: segment.kind == .pausedIndicator ? fontSize - 3 : fontSize - 0.5, weight: .medium))
                .foregroundStyle(style)
                .padding(.trailing, segment.kind == .pausedIndicator ? 4 : 0)
        } else if truncatesName {
            // The name gives way first; separator and duration stay whole.
            Text(segment.text)
                .foregroundStyle(style)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(segment.kind == .name ? 0 : 1)
        } else {
            Text(segment.text)
                .foregroundStyle(style)
        }
    }
}
