import Foundation

/// macOS 사전 글을 품사 → 뜻 → 예문으로 나눈 것. 단어 카드가 한국어 뜻 아래에 그린다.
/// 영영사전 모양: `meet | mēt | verb 1 [with object] come together: they met at noon | we met. • … 2 … noun …`
/// 다른 모양(영한 등)이라 나눌 수 없으면 글 전체를 뜻 하나로 둔다.
nonisolated struct SystemDictionaryArticle: Hashable, Sendable {
    struct Sense: Hashable, Sendable {
        /// 사전의 뜻 번호. 딸린 뜻(•)이나 뜻이 하나면 nil.
        var number: String?
        var text: String
        var examples: [String] = []
    }

    struct Section: Hashable, Sendable {
        var partOfSpeech: String?
        var senses: [Sense]
    }

    var sections: [Section]

    var senseCount: Int { sections.reduce(0) { $0 + $1.senses.count } }

    init?(_ raw: String) {
        let text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let parts = text.components(separatedBy: " | ")
        if parts.count >= 3 {
            sections = Self.sections(of: Self.droppingTail(parts[2...].joined(separator: " | ")))
        } else {
            sections = []
        }
        if sections.isEmpty {
            sections = [Section(partOfSpeech: nil, senses: [Sense(text: text)])]
        }
    }

    /// 품사마다 앞의 `limit`개 뜻만 남긴다.
    func prefix(_ limit: Int) -> [Section] {
        sections.map { Section(partOfSpeech: $0.partOfSpeech, senses: Array($0.senses.prefix(limit))) }
    }

    // MARK: - 나누기

    private static let partsOfSpeech = [
        "transitive verb", "intransitive verb", "modal verb", "auxiliary verb", "phrasal verb", "plural noun",
        "proper noun", "cardinal number", "noun", "verb", "adjective", "adverb", "preposition", "conjunction",
        "pronoun", "possessive determiner", "determiner", "exclamation", "abbreviation", "contraction",
    ]

    /// 숙어·파생어·어원은 카드에 넣지 않는다.
    private static func droppingTail(_ body: String) -> String {
        let pattern = #" (PHRASES|PHRASAL VERBS|DERIVATIVES|ORIGIN|USAGE) "#
        guard let range = body.range(of: pattern, options: .regularExpression) else { return body }
        return String(body[..<range.lowerBound])
    }

    /// 품사 이름은 맨 앞이나 문장이 끝난 자리에만 나온다.
    private static func sections(of body: String) -> [Section] {
        let names = partsOfSpeech.joined(separator: "|")
        let labels = "(?:(?:informal|formal|archaic|dated|literary|historical) )*"
        let matches = body.matchRanges(#"(?:^|(?<=[.!?)’] ))\#(labels)(?:\#(names))(?= [\[(0-9a-z])"#)
        guard let first = matches.first, body[..<first.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return matches.enumerated().compactMap { index, range in
            let end = index + 1 < matches.count ? matches[index + 1].lowerBound : body.endIndex
            let senses = senses(of: String(body[range.upperBound..<end]))
            return senses.isEmpty ? nil : Section(partOfSpeech: String(body[range]), senses: senses)
        }
    }

    private static func senses(of section: String) -> [Sense] {
        let text = droppingLeadingForms(section)
        return numbered(text).flatMap { number, body in
            body.components(separatedBy: " • ").enumerated().compactMap { index, piece in
                sense(piece, number: index == 0 ? number : nil)
            }
        }
    }

    /// 품사 바로 뒤의 활용형 괄호 `(runs) (past ran | ran |)` 를 뺀다. `(share in)` 같은 뜻 앞 괄호는 번호 뒤에 있어 남는다.
    private static func droppingLeadingForms(_ section: String) -> String {
        var text = section.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("("), let close = text.firstIndex(of: ")") {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// `1 … 2 … 3 …` 을 차례로 나눈다. 1로 시작하지 않으면 뜻 하나.
    private static func numbered(_ text: String) -> [(String?, String)] {
        // `[with object] 1 …` 처럼 문법 표시가 번호보다 앞설 수 있다.
        let body = text.replacingOccurrences(of: #"^(\[[^\]]*\] )+(?=1 )"#, with: "", options: .regularExpression)
        guard body.hasPrefix("1 ") else { return [(nil, body)] }
        var result: [(String?, String)] = []
        var rest = String(body.dropFirst(2))
        var number = 1
        while let next = rest.matchRanges(#"(?<=[.!?)’]) \#(number + 1) (?=[\[(a-zA-Z])"#).first {
            result.append((String(number), String(rest[..<next.lowerBound])))
            rest = String(rest[next.upperBound...])
            number += 1
        }
        result.append((number == 1 ? nil : String(number), rest))
        return result
    }

    private static func sense(_ piece: String, number: String?) -> Sense? {
        // 괄호 안 활용형의 발음 `(plural pennies | ˈpenēz |)` 도 뺀다.
        let plain = droppingGrammar(piece)
            .replacingOccurrences(of: #" \| [^|()]{1,30} \|(?=[),;])"#, with: "", options: .regularExpression)
        // 뜻: 예문 | 예문
        let colon = plain.range(of: ": ")
        let text = tidy(String(plain[..<(colon?.lowerBound ?? plain.endIndex)]))
        guard !text.isEmpty else { return nil }
        let examples = colon.map { plain[$0.upperBound...].components(separatedBy: " | ").map(tidy).filter { !$0.isEmpty } } ?? []
        return Sense(number: number, text: text, examples: examples)
    }

    /// `[with object]` 같은 문법 표시를 뺀다.
    private static func droppingGrammar(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[[^\]]*\]\s*:?\s*"#, with: "", options: .regularExpression)
    }

    private static func tidy(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ";,:|")))
        if result.hasSuffix("."), !result.hasSuffix("..") { result.removeLast() }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

private nonisolated extension String {
    func matchRanges(_ pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self) }
    }
}
