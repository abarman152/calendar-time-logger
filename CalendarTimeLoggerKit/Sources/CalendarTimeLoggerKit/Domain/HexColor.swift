import Foundation

/// A platform-neutral sRGB color stored as a hex string (`#RRGGBB`).
public struct HexColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    public var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    // Encoded as a hex string so stored JSON stays readable and stable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = HexColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex color \(string)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// Named colors offered in the template editor. Users can also pick any color.
public enum TemplatePalette {
    public static let colors: [(name: String, color: HexColor)] = [
        ("Blue", HexColor(hex: "#0A84FF")!),
        ("Green", HexColor(hex: "#30D158")!),
        ("Red", HexColor(hex: "#FF453A")!),
        ("Orange", HexColor(hex: "#FF9F0A")!),
        ("Yellow", HexColor(hex: "#FFD60A")!),
        ("Teal", HexColor(hex: "#40C8E0")!),
        ("Indigo", HexColor(hex: "#5E5CE6")!),
        ("Purple", HexColor(hex: "#BF5AF2")!),
        ("Pink", HexColor(hex: "#FF375F")!),
        ("Brown", HexColor(hex: "#AC8E68")!),
        ("Gray", HexColor(hex: "#8E8E93")!)
    ]

    public static func name(for color: HexColor) -> String? {
        colors.first { $0.color == color }?.name
    }
}
