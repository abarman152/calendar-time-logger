import Foundation

enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}

public enum TagParsing {
    /// Parses `"#coding, development  #swift"` into `["coding", "development", "swift"]`.
    public static func parse(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        return normalize(text.components(separatedBy: separators))
    }

    /// Trims, strips leading `#`, lowercases, and removes duplicates while keeping order.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while tag.hasPrefix("#") { tag.removeFirst() }
            tag = tag.lowercased()
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    public static func display(_ tags: [String]) -> String {
        tags.map { "#\($0)" }.joined(separator: " ")
    }
}
