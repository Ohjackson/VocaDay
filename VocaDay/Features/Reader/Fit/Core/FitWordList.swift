import Foundation

/// 순위가 있는 단어 목록 하나 (NGSL, TSL, 기본 단어장). 언어와 무관하다.
nonisolated struct FitWordList: Sendable, Hashable {
    var name: String
    /// 순위 순서의 표제어. 모두 정규화된 값.
    var headwords: [String]
    /// 변화형 → 표제어. 표제어 자신도 들어 있다.
    var formIndex: [String: String]

    init(name: String, entries: [(headword: String, forms: [String])]) {
        self.name = name
        var headwords: [String] = []
        var index: [String: String] = [:]
        for entry in entries where !entry.headword.isEmpty {
            guard index[entry.headword] != entry.headword else { continue }
            headwords.append(entry.headword)
            index[entry.headword] = entry.headword
            for form in entry.forms where index[form] == nil {
                index[form] = entry.headword
            }
        }
        self.headwords = headwords
        self.formIndex = index
    }

    static func == (lhs: FitWordList, rhs: FitWordList) -> Bool { lhs.name == rhs.name && lhs.headwords == rhs.headwords }
    func hash(into hasher: inout Hasher) { hasher.combine(name); hasher.combine(headwords.count) }

    var count: Int { headwords.count }

    /// 상위 `limit`개 표제어.
    func top(_ limit: Int) -> Set<String> { Set(headwords.prefix(max(0, limit))) }

    /// 토큰 열쇠 중 이 목록에 있는 첫 표제어.
    func headword(for keys: [String]) -> String? {
        for key in keys { if let hit = formIndex[key] { return hit } }
        return nil
    }

    /// `Resources/Wordlists/*.txt` 형식: `#` 머리 주석, 줄마다 "표제어,변화형,...", 줄 순서가 순위.
    static func parse(name: String, text: String, normalize: (String) -> String) -> FitWordList {
        var entries: [(String, [String])] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ",").map { normalize(String($0)) }.filter { !$0.isEmpty }
            guard let head = parts.first else { continue }
            entries.append((head, Array(parts.dropFirst())))
        }
        return FitWordList(name: name, entries: entries)
    }
}

/// 분석에 쓰는 공통 목록. 사용자와 무관하므로 한 번 읽어 둔다.
nonisolated struct FitReferenceLists: Sendable, Hashable {
    /// 고빈도 단어(NGSL). 아는 단어 기본값의 바탕.
    var general: FitWordList
    /// 시험 단어(TSL + 기본 단어장). 토익 단어 밀도를 센다.
    var exam: FitWordList
    /// 순위 없이 늘 아는 단어로 보는 목록 (NGSL 보충: 요일·달·수 단어, 자체 보충: a.m. 등).
    var supplement: FitWordList
    /// 출처 표시용. 예: ["NGSL 2809", "TSL 1250", "기본 단어장 2391"]
    var sources: [String]

    /// 캐시 열쇠에 들어간다.
    var fingerprint: String {
        StableHash.of(general.headwords + ["|"] + exam.headwords + ["|"] + supplement.headwords)
    }

    static let empty = FitReferenceLists(
        general: FitWordList(name: "NGSL", entries: []),
        exam: FitWordList(name: "TOEIC", entries: []),
        supplement: FitWordList(name: "Supplement", entries: []),
        sources: []
    )

    /// 토큰 열쇠가 가리키는 모든 목록 표제어.
    func listedHeadwords(for key: String) -> [String] {
        [general.formIndex[key], exam.formIndex[key], supplement.formIndex[key]].compactMap { $0 }
    }
}

nonisolated extension FitReferenceLists {
    /// 기본 단어장 단어 중 이 순위 안의 고빈도 단어는 토익 단어 목록에 넣지 않는다.
    static let commonWordCutoff = 1000

    /// 앱 번들의 영어 목록. `BundledWords.json`(로컬 전용)이 없으면 TSL 만으로 토익 단어를 센다.
    static func englishBundled(bundle: Bundle = .main, lemmatizer: any Lemmatizer = FitEnglishLemmatizer(), includeBundledWords: Bool = true) -> FitReferenceLists {
        let normalize = { lemmatizer.normalize($0) }
        let ngsl = load(resource: "NGSL", name: "NGSL", bundle: bundle, normalize: normalize)
        let tsl = load(resource: "TSL", name: "TSL", bundle: bundle, normalize: normalize)
        // 기본 단어장에는 near·meet 같은 기초 단어도 있다. 고빈도 상위 1,000개 안의 단어는 토익 단어로 세지 않는다
        // (TSL 도 NGSL 밖 단어만 담는다). 아는 단어 판정(단어장 단계)에는 영향이 없다.
        let common = ngsl.top(commonWordCutoff)
        let bundled = includeBundledWords ? bundledWordHeadwords(bundle: bundle, normalize: normalize).filter { !common.contains($0) } : []
        let sup = load(resource: "NGSL_SUP", name: "NGSL_SUP", bundle: bundle, normalize: normalize)
        let basic = load(resource: "Basic", name: "Basic", bundle: bundle, normalize: normalize)
        let supplement = FitWordList(name: "Supplement", entries: [sup, basic].flatMap { list in
            var forms: [String: [String]] = [:]
            for (form, head) in list.formIndex where form != head { forms[head, default: []].append(form) }
            return list.headwords.map { (headword: $0, forms: forms[$0] ?? []) }
        })

        var tslForms: [String: [String]] = [:]
        for (form, head) in tsl.formIndex where form != head { tslForms[head, default: []].append(form) }
        var examEntries = tsl.headwords.map { (headword: $0, forms: tslForms[$0] ?? []) }
        let tslHeads = Set(tsl.headwords)
        // 기본 단어장에는 변화형이 없다. NGSL 에 같은 표제어가 있으면 그 변화형을 빌린다 (supplier → suppliers).
        var ngslForms: [String: [String]] = [:]
        for (form, head) in ngsl.formIndex where form != head { ngslForms[head, default: []].append(form) }
        examEntries += bundled.filter { !tslHeads.contains($0) }.map { (headword: $0, forms: ngslForms[$0] ?? []) }

        var sources = ["NGSL \(ngsl.count)+\(sup.count)", "TSL \(tsl.count)"]
        if !bundled.isEmpty { sources.append("기본 단어장 \(bundled.count)") }
        return FitReferenceLists(general: ngsl, exam: FitWordList(name: "TOEIC", entries: examEntries), supplement: supplement, sources: sources)
    }

    private static func load(resource: String, name: String, bundle: Bundle, normalize: (String) -> String) -> FitWordList {
        guard let url = bundle.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return FitWordList(name: name, entries: [])
        }
        return parse(text: text, name: name, normalize: normalize)
    }

    private static func parse(text: String, name: String, normalize: (String) -> String) -> FitWordList {
        FitWordList.parse(name: name, text: text, normalize: normalize)
    }

    /// 기본 단어장의 한 단어 표제어만 (구 표제어 "take charge of" 는 한 토큰과 맞출 수 없어 뺀다).
    static func bundledWordHeadwords(bundle: Bundle, normalize: (String) -> String) -> [String] {
        struct Entry: Decodable { var english: String }
        guard let url = bundle.url(forResource: "BundledWords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        var seen = Set<String>()
        return entries.compactMap { entry in
            let word = normalize(entry.english)
            guard !word.isEmpty, !word.contains(" "), seen.insert(word).inserted else { return nil }
            return word
        }
    }
}

/// 기기·실행마다 같은 값이 나오는 해시 (Swift `Hasher` 는 실행마다 바뀐다). 디스크 캐시 열쇠에 쓴다.
nonisolated enum StableHash {
    static func of(_ parts: [String]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for part in parts {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            hash ^= 0x1F
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func of(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
