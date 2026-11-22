import Foundation
#if os(macOS)
import CoreServices
#endif

/// macOS 사전 앱의 글로 뜻을 채운다. 책 사전·기본 단어장·만든 뜻에 없을 때 마지막으로 쓴다.
/// iOS는 사전 글을 꺼내는 공개 API가 없어 이 단계를 쓰지 않는다 (단어 글자를 누르면 사전 화면을 연다).
nonisolated struct SystemDictionaryLookupStep: WordLookupStep {
    static var isSupported: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// 사전 글을 가져오는 곳. 테스트에서 바꿔 끼운다.
    var definition: @Sendable (String) -> String? = Self.systemDefinition

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        // 원형 먼저 (사전은 활용형도 받지만 원형 항목이 더 정확하다), 그다음 본문 모양.
        let terms = request.lemmas + [request.surface]
        var tried = Set<String>()
        for term in terms where tried.insert(term).inserted {
            guard let raw = definition(term), let entry = SystemDictionaryEntry(raw) else { continue }
            return WordLookupResult(
                headword: entry.headword ?? term,
                surface: request.surface,
                partOfSpeech: entry.partOfSpeech,
                meaning: entry.meaning,
                note: nil,
                toeicTag: nil,
                source: .systemDictionary
            )
        }
        return nil
    }

    static func systemDefinition(_ term: String) -> String? {
        #if os(macOS)
        let text = term as NSString
        guard text.length > 0,
              let definition = DCSCopyTextDefinition(nil, text, CFRange(location: 0, length: text.length))
        else { return nil }
        return definition.takeRetainedValue() as String
        #else
        return nil
        #endif
    }
}

/// 사전 글 한 덩어리를 상자에 맞게 줄인 것.
/// 영영사전 모양: `arrive ar·rive | əˈrīv | verb [no object] reach a place …: we arrived at … • (of a thing) …`
/// 다른 사전(영한 등)이 기본이면 앞부분만 짧게 자른다.
nonisolated struct SystemDictionaryEntry: Hashable, Sendable {
    var headword: String?
    var partOfSpeech: String?
    var meaning: String

    static let maxLength = 140

    init?(_ raw: String) {
        let text = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let parts = text.components(separatedBy: " | ")
        if parts.count >= 3 {
            // 0: "arrive ar·rive", 1: 발음, 2…: 본문
            headword = parts[0].split(separator: " ").first.map(String.init)
            var body = parts[2...].joined(separator: " | ")
            if let (pos, rest) = Self.leadingPartOfSpeech(body) {
                partOfSpeech = pos
                body = rest
            }
            meaning = Self.firstSense(body)
        } else {
            headword = nil
            partOfSpeech = nil
            meaning = Self.clip(text)
        }
        guard !meaning.isEmpty else { return nil }
    }

    private static let partsOfSpeech: [(String, String)] = [
        ("noun", "n."), ("verb", "v."), ("adjective", "adj."), ("adverb", "adv."),
        ("preposition", "prep."), ("conjunction", "conj."), ("pronoun", "pron."),
        ("exclamation", "int."), ("phrasal verb", "phr."),
    ]

    private static func leadingPartOfSpeech(_ body: String) -> (String, String)? {
        for (word, short) in partsOfSpeech where body.lowercased().hasPrefix(word + " ") {
            return (short, String(body.dropFirst(word.count + 1)))
        }
        return nil
    }

    /// 첫 뜻만: 문법 표시([with object])·번호를 빼고, 예문(:)·다음 뜻(•, 2) 앞에서 자른다.
    private static func firstSense(_ body: String) -> String {
        var sense = body.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if sense.hasPrefix("1 ") { sense = String(sense.dropFirst(2)) }
        for stop in [":", " • ", " 2 ", " DERIVATIVES", " PHRASES", " ORIGIN"] {
            if let range = sense.range(of: stop) {
                sense = String(sense[..<range.lowerBound])
            }
        }
        return clip(sense.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ";,"))))
    }

    private static func clip(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        let cut = text.prefix(maxLength)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}
