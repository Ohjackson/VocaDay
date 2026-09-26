import Foundation

/// 시험 로직(SessionPlanner·AnswerGrader)이 쓰는 단어 스냅샷. SwiftData와 분리돼 있어 단위 테스트에서 바로 만든다.
nonisolated struct QuizWord: Equatable, Sendable, Identifiable {
    var id: UUID
    var term: String
    /// 화면에 보이는 한국어 뜻. 보강됐으면 대표 뜻 1개, 아니면 사용자가 적은 뜻(품사 약어 제거).
    var meaningKo: String
    var pos: String = ""
    var cefr: String = ""
    var disambiguationKo: String = ""
    var forms: [String: String] = [:]
    var termVariants: [String] = []
    var example: String = ""
    var exampleKo: String = ""
    var clozeSentence: String = ""
    var clozeAnswer: String = ""
    var clozeForm: String = ""
    var clozeAccepted: [String] = []
    var nearMiss: [String] = []
    var isEnriched: Bool = false
    var card: SRSCardState = .initial
    var createdAt: Date = Date()
    /// 빈칸 정답의 활용 분류 (보기를 같은 형태끼리 고르는 데 쓴다).
    var clozeFormClass: LocalCloze.FormClass = .other
    /// 품사 후보. 보강됐으면 `pos` 하나, 아니면 사용자 뜻의 품사 약어("v.", "n.")에서 뽑는다.
    var posHints: Set<String> = []

    func form(_ key: String) -> String {
        forms[key] ?? ""
    }

    /// 빈칸 고르기·빈칸 쓰기를 낼 수 있는지. 보강 데이터 또는 예문에서 만든 로컬 빈칸이 있어야 한다.
    var hasCloze: Bool {
        clozeSentence.contains("<>") && !clozeAnswer.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 짝 맞추기 모호성 판정용 뜻 키.
    var meaningKeys: Set<String> {
        ExamText.meaningKeys(meaningKo)
    }

    /// 표제어·활용형·철자 변형 (정규화).
    var allFormsNormalized: Set<String> {
        var values = Set(WordEntry.formKeys.map(form).filter { !$0.isEmpty }.map(ExamText.normalize))
        values.insert(ExamText.normalize(term))
        values.formUnion(termVariants.map(ExamText.normalize))
        return values
    }

    func meaningsOverlap(with other: QuizWord) -> Bool {
        !meaningKeys.isDisjoint(with: other.meaningKeys)
    }
}

extension QuizWord {
    init(entry: WordEntry, id: UUID = UUID(), card: SRSCardState = .initial, createdAt: Date = Date()) {
        self.init(
            id: id,
            term: entry.term,
            meaningKo: entry.meaningKo,
            pos: entry.pos,
            cefr: entry.cefr,
            disambiguationKo: entry.disambiguationKo,
            forms: entry.normalizedForms,
            termVariants: entry.termVariants,
            example: entry.example,
            exampleKo: entry.exampleKo,
            clozeSentence: entry.clozeSentence,
            clozeAnswer: entry.clozeAnswer,
            clozeForm: entry.clozeForm,
            clozeAccepted: entry.clozeAccepted,
            nearMiss: entry.nearMissSynonyms,
            isEnriched: true,
            card: card,
            createdAt: createdAt,
            clozeFormClass: LocalCloze.FormClass(enrichedForm: entry.clozeForm),
            posHints: entry.pos.isEmpty ? [] : [entry.pos]
        )
    }
}

extension QuizWord {
    /// 보강 전 단어: 사용자가 적은 뜻·예문만으로 만든다. 예문에서 단어를 찾으면 빈칸 문제도 낼 수 있다.
    /// 예문의 몇 번째 줄로 빈칸을 만들었는지에 맞춰 번역 줄도 고른다.
    static func local(
        id: UUID = UUID(),
        term: String,
        meaningKo: String,
        exampleEn: String,
        exampleKo: String,
        card: SRSCardState = .initial,
        createdAt: Date = Date(),
        exampleSeed: Int = 0
    ) -> QuizWord {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let posHints = ExamText.partOfSpeechHints(meaningKo)
        let cloze = WordDataCheck.cloze(term: term, meaningKo: meaningKo, exampleEn: exampleEn, lineSeed: exampleSeed)
        let englishLines = LocalCloze.exampleLines(exampleEn)
        let koreanLines = LocalCloze.exampleLines(exampleKo)
        let lineIndex = cloze.flatMap { englishLines.firstIndex(of: $0.example) } ?? 0
        let exampleKoLine = koreanLines.indices.contains(lineIndex) ? koreanLines[lineIndex] : (koreanLines.first ?? "")

        return QuizWord(
            id: id,
            term: term,
            meaningKo: ExamText.strippingPartOfSpeechMarkers(meaningKo),
            example: cloze?.example ?? ExamText.firstExampleLine(exampleEn),
            exampleKo: exampleKoLine,
            clozeSentence: cloze?.sentence ?? "",
            clozeAnswer: cloze?.answer ?? "",
            isEnriched: false,
            card: card,
            createdAt: createdAt,
            clozeFormClass: cloze?.formClass ?? .other,
            posHints: posHints
        )
    }
}

// MARK: - VocaWord ↔ 시험 데이터

extension VocaWord {
    /// 보강 기준이 되는 사용자 입력의 지문. 사용자가 단어를 고치면 달라진다 (SPEC §1.1 needsEnrichment 대체).
    var quizSourceFingerprint: String {
        let source = [english, meaningKo, exampleEn]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\u{1F}")
        return String(ExamText.stableHash(source), radix: 16)
    }

    var isQuizEnrichmentCurrent: Bool {
        quizEnrichmentVersion >= EnrichmentService.enrichmentVersion
            && quizEnrichmentFingerprint == quizSourceFingerprint
            && !quizClozeSentence.isEmpty
    }

    var needsQuizEnrichment: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isQuizEnrichmentCurrent
    }

    var enrichmentInput: EnrichmentInput {
        EnrichmentInput(
            id: id,
            term: english.trimmingCharacters(in: .whitespacesAndNewlines),
            userMeaningKo: ExamText.strippingPartOfSpeechMarkers(meaningKo),
            userExample: ExamText.firstExampleLine(exampleEn),
            fingerprint: quizSourceFingerprint
        )
    }

    /// 검증을 통과한 보강 결과를 저장한다. 사용자 필드는 비어 있을 때만 채운다 (SPEC §6.2).
    func applyEnrichment(_ entry: WordEntry, fingerprint: String) {
        quizPos = entry.pos
        quizCefr = entry.cefr
        quizMeaningKo = entry.meaningKo.trimmingCharacters(in: .whitespacesAndNewlines)
        quizDisambiguationKo = entry.disambiguationKo
        quizFormsJSON = Self.encodeJSON(entry.normalizedForms)
        quizTermVariantsJSON = Self.encodeJSON(entry.termVariants)
        quizExample = entry.example
        quizExampleKo = entry.exampleKo
        quizClozeSentence = entry.clozeSentence
        quizClozeAnswer = entry.clozeAnswer
        quizClozeForm = entry.clozeForm
        quizClozeAcceptedJSON = Self.encodeJSON(entry.clozeAccepted)
        quizNearMissJSON = Self.encodeJSON(entry.nearMissSynonyms)
        quizEnrichmentVersion = EnrichmentService.enrichmentVersion
        quizEnrichmentFingerprint = fingerprint

        if meaningKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meaningKo = entry.meaningKo
        }
    }

    var quizWord: QuizWord { quizWord(exampleSeed: 0) }

    /// - Parameter exampleSeed: 예문이 여러 줄이면 빈칸에 쓸 줄을 고른다 (보통 학습일 번호).
    func quizWord(exampleSeed: Int) -> QuizWord {
        let userMeaning = ExamText.strippingPartOfSpeechMarkers(meaningKo)
        guard isQuizEnrichmentCurrent else {
            return localQuizWord(exampleSeed: exampleSeed)
        }
        return QuizWord(
            id: id,
            term: english.trimmingCharacters(in: .whitespacesAndNewlines),
            meaningKo: quizMeaningKo.isEmpty ? userMeaning : quizMeaningKo,
            pos: quizPos,
            cefr: quizCefr,
            disambiguationKo: quizDisambiguationKo,
            forms: Self.decodeJSON(quizFormsJSON) ?? [:],
            termVariants: Self.decodeJSON(quizTermVariantsJSON) ?? [],
            example: quizExample,
            exampleKo: quizExampleKo,
            clozeSentence: quizClozeSentence,
            clozeAnswer: quizClozeAnswer,
            clozeForm: quizClozeForm,
            clozeAccepted: Self.decodeJSON(quizClozeAcceptedJSON) ?? [],
            nearMiss: Self.decodeJSON(quizNearMissJSON) ?? [],
            isEnriched: true,
            card: srsCard,
            createdAt: createdAt,
            clozeFormClass: LocalCloze.FormClass(enrichedForm: quizClozeForm),
            posHints: quizPos.isEmpty ? ExamText.partOfSpeechHints(meaningKo) : [quizPos]
        )
    }

    private func localQuizWord(exampleSeed: Int) -> QuizWord {
        QuizWord.local(
            id: id,
            term: english,
            meaningKo: meaningKo,
            exampleEn: exampleEn,
            exampleKo: exampleKo,
            card: srsCard,
            createdAt: createdAt,
            exampleSeed: exampleSeed
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func decodeJSON<T: Decodable>(_ json: String) -> T? {
        guard !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
