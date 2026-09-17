import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Checks symbol names against the SF Symbols actually installed on the test
/// machine, independently of the generated catalog.
enum SymbolRendering {
    static func exists(_ name: String) -> Bool {
        #if canImport(AppKit)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        return true
        #endif
    }
}

enum EmojiDetection {
    /// Whether text contains an emoji presentation character or pictograph.
    static func containsEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
                || scalar.value == 0xFE0F
        }
    }
}
