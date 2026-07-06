import Foundation

enum JSONWordParser {
    static func encode(_ words: [VocaWordJSON]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(words)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ text: String) throws -> [VocaWordJSON] {
        let data = Data(text.utf8)
        return try JSONDecoder().decode([VocaWordJSON].self, from: data)
            .map { word in
                var normalized = word
                normalized.english = word.english.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized
            }
            .filter { !$0.english.isEmpty }
    }
}
