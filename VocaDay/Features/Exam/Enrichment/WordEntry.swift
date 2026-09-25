import Foundation

/// en_word_schema.json 한 항목. 키 이름은 스키마 그대로(snake_case).
nonisolated struct WordEntry: Codable, Equatable, Sendable {
    static let formKeys = [
        "base", "past", "past_participle", "present_participle",
        "third_person", "plural", "comparative", "superlative",
    ]

    var id: String?
    var term: String
    var pos: String
    var cefr: String
    var meaningKo: String
    var disambiguationKo: String
    var nearMissSynonyms: [String]
    var forms: [String: String]
    var termVariants: [String]
    var example: String
    var exampleKo: String
    var clozeSentence: String
    var clozeAnswer: String
    var clozeForm: String
    var clozeAccepted: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case pos
        case cefr
        case meaningKo = "meaning_ko"
        case disambiguationKo = "disambiguation_ko"
        case nearMissSynonyms = "near_miss_synonyms"
        case forms
        case termVariants = "term_variants"
        case example
        case exampleKo = "example_ko"
        case clozeSentence = "cloze_sentence"
        case clozeAnswer = "cloze_answer"
        case clozeForm = "cloze_form"
        case clozeAccepted = "cloze_accepted"
    }

    init(
        id: String? = nil,
        term: String,
        pos: String = "",
        cefr: String = "",
        meaningKo: String = "",
        disambiguationKo: String = "",
        nearMissSynonyms: [String] = [],
        forms: [String: String] = [:],
        termVariants: [String] = [],
        example: String = "",
        exampleKo: String = "",
        clozeSentence: String = "",
        clozeAnswer: String = "",
        clozeForm: String = "",
        clozeAccepted: [String] = []
    ) {
        self.id = id
        self.term = term
        self.pos = pos
        self.cefr = cefr
        self.meaningKo = meaningKo
        self.disambiguationKo = disambiguationKo
        self.nearMissSynonyms = nearMissSynonyms
        self.forms = forms
        self.termVariants = termVariants
        self.example = example
        self.exampleKo = exampleKo
        self.clozeSentence = clozeSentence
        self.clozeAnswer = clozeAnswer
        self.clozeForm = clozeForm
        self.clozeAccepted = clozeAccepted
    }

    /// 모델 응답에서 빠진 키는 빈 값으로 채워 검증 단계에서 걸러지게 한다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        term = try container.decodeIfPresent(String.self, forKey: .term) ?? ""
        pos = try container.decodeIfPresent(String.self, forKey: .pos) ?? ""
        cefr = try container.decodeIfPresent(String.self, forKey: .cefr) ?? ""
        meaningKo = try container.decodeIfPresent(String.self, forKey: .meaningKo) ?? ""
        disambiguationKo = try container.decodeIfPresent(String.self, forKey: .disambiguationKo) ?? ""
        nearMissSynonyms = try container.decodeIfPresent([String].self, forKey: .nearMissSynonyms) ?? []
        forms = try container.decodeIfPresent([String: String].self, forKey: .forms) ?? [:]
        termVariants = try container.decodeIfPresent([String].self, forKey: .termVariants) ?? []
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        exampleKo = try container.decodeIfPresent(String.self, forKey: .exampleKo) ?? ""
        clozeSentence = try container.decodeIfPresent(String.self, forKey: .clozeSentence) ?? ""
        clozeAnswer = try container.decodeIfPresent(String.self, forKey: .clozeAnswer) ?? ""
        clozeForm = try container.decodeIfPresent(String.self, forKey: .clozeForm) ?? ""
        clozeAccepted = try container.decodeIfPresent([String].self, forKey: .clozeAccepted) ?? []
    }

    func form(_ key: String) -> String {
        forms[key] ?? ""
    }

    /// 모든 키를 채운 forms (없는 키는 "").
    var normalizedForms: [String: String] {
        Dictionary(uniqueKeysWithValues: Self.formKeys.map { ($0, forms[$0] ?? "") })
    }
}
