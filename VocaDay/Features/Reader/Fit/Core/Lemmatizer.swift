import Foundation
import NaturalLanguage

// 적합도 검사 코어. 앱 모델(VocaWord 등)을 쓰지 않는다. 언어에 묶인 부분은 이 파일의 프로토콜 뒤에 둔다.

/// 본문 한 토큰. 원형 세기와 고유명사·숫자 제외의 단위.
nonisolated struct FitToken: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable, Codable {
        /// 세는 단어.
        case word
        /// 사람·장소·회사 이름. 아는 단어 비율에서 뺀다.
        case properNoun
        /// 숫자(12, twenty-first 가 아닌 12th, 3.5 등). 뺀다.
        case number
    }

    /// 본문에 나온 모양 그대로.
    var surface: String
    /// 단어 목록과 맞춰 볼 열쇠들. 첫 값이 대표 원형이다. 모두 `Lemmatizer.normalize` 를 거친 값.
    var keys: [String]
    /// 하이픈 단어(last-minute)의 조각. 통째로는 어느 목록에도 없을 때 조각이 모두 아는 단어면 아는 단어로 본다.
    var compoundParts: [String] = []
    var kind: Kind
    /// 문장 첫 단어인지. 대문자 고유명사 추정에 쓴다.
    var isSentenceInitial: Bool

    var lemma: String { keys.first ?? surface }
}

/// 언어별 원형 분석. 영어는 `FitEnglishLemmatizer`(NLTagger), 일본어 앱은 형태소 분석기로 바꾼다.
nonisolated protocol Lemmatizer: Sendable {
    /// 캐시 열쇠에 들어간다. 분석 규칙을 바꾸면 값을 바꾼다.
    var identifier: String { get }
    /// 문장 하나를 토큰으로 나눈다. 기호·공백은 넣지 않는다.
    func tokens(in sentence: String) -> [FitToken]
    /// 단어 목록·단어장 표제어를 본문 열쇠와 같은 모양으로 맞춘다 (영어: 소문자, 둥근 따옴표 → ').
    func normalize(_ word: String) -> String
}

/// 언어별 문장 규칙. 품질 경고에 쓴다.
nonisolated struct FitLanguageRules: Sendable {
    /// 문장 끝에 와야 하는 글자. 닫는 따옴표·괄호는 건너뛰고 본다.
    var sentenceTerminators: Set<Character>
    var closingMarks: Set<Character>
    /// 이 토큰 수 이상이면 "아주 긴 문장".
    var longSentenceTokenCount: Int
    /// 정상 글자인지. 아니면 깨진 글자(OCR)로 센다.
    var isExpectedCharacter: @Sendable (Character) -> Bool
    /// 마침표 없이 끝나도 되는 줄(이메일 머리줄, 일정표 줄 등)인지.
    var allowsUnterminated: @Sendable (String) -> Bool

    static let english = FitLanguageRules(
        sentenceTerminators: [".", "!", "?", "…"],
        closingMarks: ["\"", "'", "”", "’", ")", "]"],
        longSentenceTokenCount: 60,
        isExpectedCharacter: { character in
            if character.isASCII { return !(character.asciiValue.map { $0 < 0x20 && $0 != 0x0A && $0 != 0x09 } ?? false) }
            // 영어 책에 흔히 나오는 비ASCII 글자: 둥근 따옴표, 대시, 줄임표, 악센트 라틴 글자, 통화 기호.
            if "“”‘’—–…€£¥°×·é".contains(character) { return true }
            if character.unicodeScalars.allSatisfy({ (0x00C0...0x024F).contains($0.value) }) { return true }
            return false
        },
        allowsUnterminated: { text in
            // 생성 책: 이메일·일정표 머리줄("To: ...", "10:00 a.m. — ...")은 마침표가 없을 수 있다.
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let colon = trimmed.firstIndex(of: ":"), trimmed.distance(from: trimmed.startIndex, to: colon) <= 24 { return true }
            if trimmed.contains(" — ") || trimmed.hasPrefix("—") || trimmed.hasPrefix("-") || trimmed.hasPrefix("•") { return true }
            // 편지 인사·맺음말("Dear Ms. Seo,", "Sincerely, Leo Marsh"), 대문자 제목 줄("MEMO").
            if trimmed.hasSuffix(",") { return true }
            let lowered = trimmed.lowercased()
            if ["sincerely", "best regards", "regards", "kind regards", "best wishes", "yours", "thank you", "thanks"].contains(where: { lowered.hasPrefix($0) }) { return true }
            if trimmed.contains(where: \.isLetter), !trimmed.contains(where: \.isLowercase) { return true }
            return false
        }
    )
}

/// NLTagger `.lemma` + `.nameTypeOrLexicalClass` 로 영어 원형을 센다.
nonisolated struct FitEnglishLemmatizer: Lemmatizer {
    var identifier: String { "en-nltagger-1" }

    func normalize(_ word: String) -> String {
        word.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tokens(in sentence: String) -> [FitToken] {
        guard !sentence.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma, .nameTypeOrLexicalClass])
        tagger.string = sentence
        tagger.setLanguage(.english, range: sentence.startIndex..<sentence.endIndex)
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther, .joinContractions]

        var result: [FitToken] = []
        tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, range in
            let surface = String(sentence[range])
            guard surface.contains(where: \.isLetter) || surface.contains(where: \.isNumber) else { return true }
            let isInitial = result.isEmpty

            if !surface.contains(where: \.isLetter) || tag == .number && surface.contains(where: \.isNumber) {
                result.append(FitToken(surface: surface, keys: [surface], kind: .number, isSentenceInitial: isInitial))
                return true
            }

            let kind: FitToken.Kind = (tag == .personalName || tag == .placeName || tag == .organizationName) ? .properNoun : .word
            let lemmaTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let keys = keys(surface: surface, lemma: lemmaTag)
            let parts = surface.contains("-") ? Self.stripClitics(normalize(surface)).split(separator: "-").map(String.init).filter { $0.count > 1 } : []
            result.append(FitToken(surface: surface, keys: keys, compoundParts: parts, kind: kind, isSentenceInitial: isInitial))
            return true
        }
        return result
    }

    /// 대표 원형을 앞에 두고, 소유격·축약을 떼어 낸 모양을 뒤에 둔다.
    private func keys(surface: String, lemma: String?) -> [String] {
        let base = Self.stripClitics(normalize(surface))
        var keys: [String] = []
        func add(_ key: String?) {
            guard let key, !key.isEmpty, !keys.contains(key) else { return }
            keys.append(key)
        }
        if let lemma {
            // NLTagger 는 처음 보는 단어에 원형을 주지 않거나 대문자 모양 그대로 준다.
            add(Self.stripClitics(normalize(lemma)))
        }
        add(base)
        // 태거가 원형을 못 준 경우(원형 모델이 없는 iOS 시뮬레이터, 처음 보는 단어)를 위한 규칙 후보.
        // 분석기는 이 후보 중 단어 목록·단어장에 있는 것을 쓴다.
        if keys.count == 1 {
            for candidate in Self.inflectionCandidates(base) { add(candidate) }
        }
        return keys
    }

    /// 규칙 활용형 → 원형 후보: allocated → allocat, allocate / suppliers → supplier / planning → plan.
    /// 비교급(-er, -est)은 manager → manage 같은 오판이 많아 넣지 않는다 (목록 변화형이 대신 맞춘다).
    static func inflectionCandidates(_ word: String) -> [String] {
        guard word.count > 3, word.allSatisfy({ $0.isLetter }) else { return [] }
        var result: [String] = []
        func stem(_ suffix: String) -> String? {
            word.hasSuffix(suffix) && word.count - suffix.count >= 2 ? String(word.dropLast(suffix.count)) : nil
        }
        func undoubled(_ stem: String) -> String? {
            guard let last = stem.last, stem.count >= 3, stem.dropLast().last == last, !"aeiouslz".contains(last) else { return nil }
            return String(stem.dropLast())
        }
        if let s = stem("ies") { result.append(s + "y") }
        if let s = stem("ied") { result.append(s + "y") }
        if let s = stem("es") { result.append(s) }
        if let s = stem("s"), !word.hasSuffix("ss") { result.append(s) }
        if let s = stem("ed") {
            result.append(s + "e")
            result.append(s)
            if let u = undoubled(s) { result.append(u) }
        }
        if let s = stem("ing") {
            result.append(s + "e")
            result.append(s)
            if let u = undoubled(s) { result.append(u) }
        }
        return result
    }

    /// didn't → did, Mina's → mina, they're → they, can't → can, won't → will.
    static func stripClitics(_ word: String) -> String {
        var word = word
        for suffix in ["n't", "'s", "'re", "'ll", "'ve", "'d", "'m", "s'"] where word.hasSuffix(suffix) && word.count > suffix.count {
            word = String(word.dropLast(suffix == "s'" ? 1 : suffix.count))
            if suffix == "n't" {
                switch word {
                case "ca": word = "can"
                case "wo": word = "will"
                case "sha": word = "shall"
                default: break
                }
            }
            break
        }
        return word.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
    }
}
