import Foundation

/// SPEC §6.3 검증 실패 코드. rawValue는 validate_reference.py 의 코드와 같다.
nonisolated enum EntryValidationError: Equatable, Hashable, Sendable, CustomStringConvertible {
    case empty(String)
    case termMismatch
    case pos
    case cefr
    case restore
    case form
    case base
    case formsPos
    case firstWord
    case articleHint
    case `repeat`
    case hangul
    case meaningLength
    case disambiguationLength
    case exampleLength
    case nearMiss

    var code: String {
        switch self {
        case .empty(let field): "empty:\(field)"
        case .termMismatch: "term_mismatch"
        case .pos: "pos"
        case .cefr: "cefr"
        case .restore: "restore"
        case .form: "form"
        case .base: "base"
        case .formsPos: "forms_pos"
        case .firstWord: "first_word"
        case .articleHint: "article_hint"
        case .repeat: "repeat"
        case .hangul: "hangul"
        case .meaningLength: "meaning_len"
        case .disambiguationLength: "disamb_len"
        case .exampleLength: "example_len"
        case .nearMiss: "near_miss"
        }
    }

    /// <correction> 블록에 그대로 넣는 설명.
    var description: String {
        switch self {
        case .empty(let field):
            "\(field) is empty."
        case .termMismatch:
            "term must be the requested term, unchanged except trimming and lowercasing."
        case .pos:
            "pos is not one of the allowed values."
        case .cefr:
            "cefr must be one of A1, A2, B1, B2, C1, C2."
        case .restore:
            "cloze_sentence must contain exactly one <>, and replacing <> with cloze_answer must reproduce example character for character."
        case .form:
            "cloze_answer must equal forms[cloze_form] (case-insensitive)."
        case .base:
            "forms.base must be filled and equal to term."
        case .formsPos:
            "forms has values in keys that do not apply to this pos; those keys must be \"\"."
        case .firstWord:
            "<> must not be at the start of cloze_sentence; the answer cannot be the first word of the example."
        case .articleHint:
            "The word directly before <> must not be \"a\" or \"an\"."
        case .repeat:
            "The example must use the term (any form) exactly once."
        case .hangul:
            "meaning_ko and example_ko must be written in Korean."
        case .meaningLength:
            "meaning_ko must be at most 20 characters and a single gloss."
        case .disambiguationLength:
            "disambiguation_ko must be at most 40 characters."
        case .exampleLength:
            "example must be 6–22 words and at most 200 characters."
        case .nearMiss:
            "near_miss_synonyms must have at most 4 items and must not contain the term or any of its forms."
        }
    }
}

/// SPEC §6.3 로컬 검증. docs/srs-port/samples/validate_reference.py 와 같은 결과를 내야 한다.
nonisolated enum EntryValidator {
    static let partsOfSpeech = [
        "noun", "verb", "adjective", "adverb", "phrasal_verb",
        "idiom", "preposition", "conjunction", "other",
    ]
    static let cefrLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    static let clozeForms = WordEntry.formKeys + ["other"]

    private static let allowedFormKeys: [String: Set<String>] = [
        "noun": ["base", "plural"],
        "verb": ["base", "past", "past_participle", "present_participle", "third_person"],
        "phrasal_verb": ["base", "past", "past_participle", "present_participle", "third_person"],
        "adjective": ["base", "comparative", "superlative"],
    ]

    static func allowedForms(for pos: String) -> Set<String> {
        allowedFormKeys[pos] ?? ["base"]
    }

    static func validate(_ entry: WordEntry, requestedTerm: String) -> [EntryValidationError] {
        var errors: [EntryValidationError] = []

        let required: [(String, String)] = [
            ("term", entry.term), ("pos", entry.pos), ("meaning_ko", entry.meaningKo),
            ("example", entry.example), ("example_ko", entry.exampleKo),
            ("cloze_sentence", entry.clozeSentence), ("cloze_answer", entry.clozeAnswer),
            ("cloze_form", entry.clozeForm),
        ]
        for (field, value) in required where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.empty(field))
        }
        guard errors.isEmpty else { return errors }

        if ExamText.normalize(entry.term) != ExamText.normalize(requestedTerm) {
            errors.append(.termMismatch)
        }
        if !partsOfSpeech.contains(entry.pos) {
            errors.append(.pos)
        }
        if !cefrLevels.contains(entry.cefr) {
            errors.append(.cefr)
        }

        let sentence = entry.clozeSentence
        let answer = entry.clozeAnswer
        let example = entry.example
        let blankCount = sentence.components(separatedBy: "<>").count - 1
        if blankCount != 1 || sentence.replacingOccurrences(of: "<>", with: answer) != example {
            errors.append(.restore)
        }

        if entry.clozeForm != "other", answer.lowercased() != entry.form(entry.clozeForm).lowercased() {
            errors.append(.form)
        }

        let base = entry.form("base")
        if base.isEmpty || ExamText.normalize(base) != ExamText.normalize(entry.term) {
            errors.append(.base)
        }

        let allowed = allowedForms(for: entry.pos)
        if WordEntry.formKeys.contains(where: { !allowed.contains($0) && !entry.form($0).isEmpty }) {
            errors.append(.formsPos)
        }

        let before = sentence.components(separatedBy: "<>").first ?? ""
        if before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.firstWord)
        }
        if let previousWord = ExamText.words(before).last, previousWord == "a" || previousWord == "an" {
            errors.append(.articleHint)
        }

        let exampleWords = ExamText.words(example)
        let allForms = Set(WordEntry.formKeys.map(entry.form).filter { !$0.isEmpty }).union(entry.termVariants)
        let otherFormHits = allForms
            .filter { $0.lowercased() != answer.lowercased() }
            .reduce(0) { $0 + ExamText.phraseCount(in: exampleWords, phrase: $1) }
        if otherFormHits + ExamText.phraseCount(in: exampleWords, phrase: answer) > 1 {
            errors.append(.repeat)
        }

        if !ExamText.containsHangulSyllable(entry.meaningKo) || !ExamText.containsHangulSyllable(entry.exampleKo) {
            errors.append(.hangul)
        }
        // 파이썬 len()과 같게 유니코드 스칼라 수로 센다.
        if entry.meaningKo.unicodeScalars.count > 20 {
            errors.append(.meaningLength)
        }
        if entry.disambiguationKo.unicodeScalars.count > 40 {
            errors.append(.disambiguationLength)
        }
        let exampleWordCount = example.split(whereSeparator: \.isWhitespace).count
        if !(6...22).contains(exampleWordCount) || example.unicodeScalars.count > 200 {
            errors.append(.exampleLength)
        }

        let nearMisses = entry.nearMissSynonyms.map(ExamText.normalize)
        let normalizedForms = Set(allForms.map(ExamText.normalize))
        if nearMisses.count > 4 || nearMisses.contains(where: normalizedForms.contains) {
            errors.append(.nearMiss)
        }
        return errors
    }

    /// <correction> 블록 본문.
    static func correctionMessage(for errors: [EntryValidationError]) -> String {
        errors.map { "- [\($0.code)] \($0.description)" }.joined(separator: "\n")
    }
}
