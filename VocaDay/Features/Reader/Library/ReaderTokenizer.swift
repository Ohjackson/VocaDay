import Foundation

/// 문장을 누를 단어 조각으로 나눈다. 띄어쓰기 단위로 자르고, 앞뒤 문장부호를 뺀 부분을 누를 단어로 본다.
/// (영어 전용. 일본어는 띄어쓰기가 없어 형태소 분절로 바꿔야 한다.)
nonisolated enum ReaderTokenizer {
    struct Token: Hashable, Sendable {
        /// 화면에 보이는 그대로. 예: "contracts."
        var display: String
        /// 누르면 사전에서 찾을 모양. 글자가 없으면 nil. 예: "contracts"
        var surface: String?
        /// 문장 안 위치 (UTF-16). 본문 조판(TextKit)의 글자 위치와 맞춘다.
        var range: Range<Int>
    }

    static func tokens(in sentence: String) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        var start: Int?
        var chunk = ""
        func flush() {
            guard let begin = start else { return }
            let surface = chunk.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted)
            let hasLetter = surface.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            tokens.append(Token(display: chunk, surface: hasLetter ? normalize(surface) : nil, range: begin..<offset))
            start = nil
            chunk = ""
        }
        for character in sentence {
            if character.isWhitespace {
                flush()
            } else {
                if start == nil { start = offset }
                chunk.append(character)
            }
            offset += character.utf16.count
        }
        flush()
        return tokens
    }

    /// 굽은 따옴표를 곧은 따옴표로 바꾼다. "Mina’s" → "Mina's"
    private static func normalize(_ surface: String) -> String {
        surface.replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
