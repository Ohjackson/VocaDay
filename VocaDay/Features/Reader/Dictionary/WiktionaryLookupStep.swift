import Foundation

/// 앱에 들어 있는 위키낱말사전(영→한)을 철자로 찾는다. 인터넷·언어 팩 없이 나온다.
/// 뜻 형식은 기본 단어장과 같고, 품사 안의 뜻은 "; "로 나눈다: "n. 기도; (법률) 청구 / v. 기도하다".
struct WiktionaryLookupStep: WordLookupStep {
    var index: () -> [String: String]
    /// 문장 속 품사(명사·동사)가 사전에 없으면 지나간다. 빠진 품사의 엉뚱한 뜻보다 번역이 낫다
    /// (chain은 동사 뜻만 있어서 "silver chain"에는 맞지 않는다).
    var requiresMatchingPartOfSpeech: Bool
    /// 낱말 → 문장 속 품사 약어. 테스트에서 바꿔 끼운다.
    var partOfSpeech: (_ surface: String, _ sentence: String) -> String? = EnglishPartOfSpeech.abbreviation(of:in:)

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        let words = index()
        let isPhrase = request.surface.contains(where: \.isWhitespace)
        let wanted = isPhrase ? nil : partOfSpeech(request.surface, request.sentence)
        for term in Self.candidates(request, partOfSpeech: wanted) {
            guard let meaning = words[term] else { continue }
            let segments = Self.segments(meaning)
            if requiresMatchingPartOfSpeech, !Self.covers(wanted, segments) { continue }
            return WordLookupResult(
                headword: term,
                surface: request.surface,
                partOfSpeech: nil,
                meaning: Self.ordered(segments, first: wanted),
                note: nil,
                toeicTag: nil,
                source: .wiktionary
            )
        }
        return nil
    }

    /// 본문 모양 → 원형 순서. 불규칙 동사의 변화형이면 원형이 먼저다 (found는 "설립하다"가 아니라 find의 뜻).
    static func candidates(_ request: WordLookupRequest, partOfSpeech: String?) -> [String] {
        guard partOfSpeech == "v.", let lemma = request.lemma,
              !EnglishLemmatizer.ruleLemmas(of: request.surface).contains(lemma)
        else { return request.candidates }
        return [lemma] + request.candidates.filter { $0 != lemma }
    }

    static func segments(_ meaning: String) -> [String] {
        meaning.components(separatedBy: " / ")
    }

    /// 명사 자리에 동사 뜻뿐이거나 동사 자리에 동사 뜻이 없을 때만 어긋난 것으로 본다. 나머지 품사는 구분이 애매하다.
    static func covers(_ wanted: String?, _ segments: [String]) -> Bool {
        let isVerb = segments.map { $0.hasPrefix("v. ") }
        switch wanted {
        case "n.": return isVerb.contains(false)
        case "v.": return isVerb.contains(true)
        default: return true
        }
    }

    /// 문장 속 품사의 뜻을 앞에 둔다.
    static func ordered(_ segments: [String], first wanted: String?) -> String {
        guard let wanted, let index = segments.firstIndex(where: { $0.hasPrefix(wanted + " ") }) else {
            return segments.joined(separator: " / ")
        }
        var sorted = segments
        sorted.insert(sorted.remove(at: index), at: 0)
        return sorted.joined(separator: " / ")
    }
}

/// 위키낱말사전 파일(WiktionaryEnKo.json). scripts/build_wiktionary_dictionary.py 가 만든다.
/// 라이선스가 CC BY-SA 4.0이라 출처를 「사전·음성 설정」과 카드 「⋯」 메뉴에 보인다.
nonisolated struct WiktionaryDictionary: Decodable, Sendable {
    var license: String
    var dumpDate: String
    var words: [String: String]

    static let shared: WiktionaryDictionary = load() ?? WiktionaryDictionary(license: "CC BY-SA 4.0", dumpDate: "", words: [:])

    static let siteURL = URL(string: "https://ko.wiktionary.org")!
    static let licenseURL = URL(string: "https://creativecommons.org/licenses/by-sa/4.0/deed.ko")!

    static func load(bundle: Bundle = .main) -> WiktionaryDictionary? {
        guard let url = bundle.url(forResource: "WiktionaryEnKo", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WiktionaryDictionary.self, from: data)
    }

    /// 그 낱말의 위키낱말사전 문서.
    static func pageURL(for term: String) -> URL? {
        let title = term.replacingOccurrences(of: " ", with: "_")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_'"))
        guard let escaped = title.addingPercentEncoding(withAllowedCharacters: allowed), !escaped.isEmpty else { return nil }
        return URL(string: "https://ko.wiktionary.org/wiki/\(escaped)")
    }
}
