import Foundation
import NaturalLanguage

// 영어 찾기 단계.
// 자동: 책 사전 → 원형으로 책 사전 → 기본 단어장 → 전에 기기에서 만든 뜻 → 위키낱말사전 → 기기 번역(한국어) → (Mac) 시스템 사전.
// 버튼(카드 「⋯」): 기기 안 생성. 자세한 뜻은 시스템 사전(단어 글자를 누름)에서 본다.

enum EnglishWordLookup {
    /// 단어를 누르면 바로 도는 찾기. 생성은 넣지 않는다 (사용자가 「⋯ → 기기에서 뜻 만들기」를 누를 때만).
    /// `usesSystemDictionary`: macOS에서 마지막으로 사전 앱의 글을 꺼내 보인다 (iOS는 꺼낼 API가 없어 항상 꺼짐).
    static func pipeline(
        bundledWords: @escaping () -> [String: VocaWordJSON] = { BundledWordIndex.shared },
        wiktionary: @escaping () -> [String: String] = { WiktionaryDictionary.shared.words },
        wiktionaryExamples: @escaping (String) -> [WordMeaningExample] = WiktionaryDictionary.examples(for:),
        generatedMeanings: GeneratedMeaningStore = .shared,
        usesTranslation: Bool = true,
        usesSystemDictionary: Bool = SystemDictionaryLookupStep.isSupported
    ) -> WordLookupPipeline {
        var steps: [any WordLookupStep] = [
            GlossaryLookupStep(usesLemma: false),
            GlossaryLookupStep(usesLemma: true),
            BundledPackLookupStep(index: bundledWords),
            GeneratedMeaningLookupStep(store: generatedMeanings),
            WiktionaryLookupStep(index: wiktionary, examples: wiktionaryExamples, requiresMatchingPartOfSpeech: true),
        ]
        // 한국어 뜻이 먼저. 번역 언어 팩이 없을 때만 영영사전 글로 넘어간다.
        if usesTranslation {
            steps.append(TranslationWordLookupStep())
        }
        // 번역이 안 되면 품사가 달라도 위키낱말사전 뜻을 쓴다.
        steps.append(WiktionaryLookupStep(index: wiktionary, examples: wiktionaryExamples, requiresMatchingPartOfSpeech: false))
        if usesSystemDictionary {
            steps.append(SystemDictionaryLookupStep())
        }
        return WordLookupPipeline(lemmatizer: EnglishLemmatizer(), steps: steps, examples: wiktionaryExamples)
    }

    /// 끌어 고른 여러 단어. 책 사전이나 위키낱말사전에 그 말(숙어)이 있으면 그것, 아니면 기기 번역으로 덩어리 전체를 옮긴다.
    static func phrasePipeline() -> WordLookupPipeline {
        var pipeline = WordLookupPipeline(
            lemmatizer: EnglishLemmatizer(),
            steps: [
                GlossaryLookupStep(usesLemma: false),
                WiktionaryLookupStep(
                    index: { WiktionaryDictionary.shared.words },
                    examples: WiktionaryDictionary.examples(for:),
                    requiresMatchingPartOfSpeech: false
                ),
                TranslationWordLookupStep(),
                PhraseMeaningLookupStep(),
            ],
            examples: WiktionaryDictionary.examples(for:)
        )
        pipeline.notFoundMessage = "이 말을 번역하지 못했어요."
        return pipeline
    }

    /// 「⋯ → 기기에서 뜻 만들기」. 만든 뜻은 `generatedMeanings`에 남겨 다음부터 바로 보인다.
    static func generation(
        generator: any EnglishWordGenerating = AppleFoundationWordGenerationService(),
        isGenerationEnabled: @escaping () -> Bool = { GenerationSettings.isEnabled },
        generatedMeanings: GeneratedMeaningStore = .shared
    ) -> GeneratedWordLookupStep {
        GeneratedWordLookupStep(generator: generator, isEnabled: isGenerationEnabled, store: generatedMeanings)
    }

    /// 단어 추가 화면(`AddWordsView`)과 같은 키.
    enum GenerationSettings {
        static let enabledKey = "isAppleIntelligenceWordGenerationEnabled"
        static let consentKey = "hasAcknowledgedAppleIntelligenceWordGeneration"

        static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        /// 「기기에서 뜻 만들기」를 누른 것을 단어 추가 화면의 생성 안내 확인과 같게 본다.
        static func giveConsent() { UserDefaults.standard.set(true, forKey: consentKey) }
    }
}

/// `NLTagger`의 lemma. 문장 안 쓰임을 보고 원형을 고른다 (allocated → allocate).
struct EnglishLemmatizer: WordLemmatizing {
    func normalize(_ surface: String) -> String {
        var word = surface
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        for suffix in ["'s", "s'"] where word.count > suffix.count + 1 && word.hasSuffix(suffix) {
            word = String(word.dropLast(suffix == "'s" ? 2 : 1))
            break
        }
        return word
    }

    /// `NLTagger` lemma가 먼저, 그다음 규칙 변화(-s, -ed, -ing …)를 되돌린 후보, 끝으로 흔한 단어의 변화형 표(held → hold).
    /// lemma 모델이 없는 환경(iOS 시뮬레이터 등)에서는 tagger가 nil을 주므로 규칙·표 후보로 찾는다.
    func lemmas(of surface: String, in sentence: String) -> [String] {
        let key = normalize(surface)
        guard !key.isEmpty else { return [] }
        let tagged = lemma(matching: key, in: sentence) ?? lemma(matching: key, in: key)
        return ([tagged].compactMap { $0 } + Self.ruleLemmas(of: key) + [EnglishWordForms.shared[key]].compactMap { $0 }).filter { $0 != key }
    }

    /// 규칙 변화만 되돌린다. 틀린 후보(allocat)도 섞이지만 사전에서 못 찾으면 그냥 지나간다.
    static func ruleLemmas(of word: String) -> [String] {
        guard word.count >= 4, word.allSatisfy(\.isLetter) else { return [] }
        var result: [String] = []
        func strip(_ suffix: String, add: String = "") {
            guard word.hasSuffix(suffix) else { return }
            let stem = String(word.dropLast(suffix.count))
            guard stem.count >= 2 else { return }
            result.append(stem + add)
            // planned → plan, running → run
            if add.isEmpty, suffix == "ed" || suffix == "ing",
               let last = stem.last, stem.dropLast().last == last, !"lsz".contains(last) {
                result.append(String(stem.dropLast()))
            }
        }
        strip("ies", add: "y")
        strip("ied", add: "y")
        strip("es")
        if !word.hasSuffix("ss") { strip("s") }
        strip("ed", add: "e")
        strip("ed")
        strip("ing", add: "e")
        strip("ing")
        return result
    }

    /// 만들 때 lemma 모델을 읽느라 느려서 하나를 계속 쓴다.
    private static let tagger = NLTagger(tagSchemes: [.lemma])

    private func lemma(matching key: String, in text: String) -> String? {
        guard !key.contains(where: \.isWhitespace) else { return nil }
        let tagger = Self.tagger
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var found: String?
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard normalize(String(text[range])) == key else { return true }
            found = tag?.rawValue.lowercased()
            return false
        }
        guard let found, !found.isEmpty else { return nil }
        return found
    }
}

/// 흔한 단어의 변화형 → 원형 (앱에 있는 NGSL 목록: "hold,holds,held,…"). 불규칙 변화를 되돌릴 때 쓴다.
nonisolated enum EnglishWordForms {
    static let shared: [String: String] = {
        guard let url = Bundle.main.url(forResource: "NGSL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        return parse(text)
    }()

    /// 여러 단어에 걸친 변화형은 앞(더 흔한 단어)의 것.
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let forms = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard let headword = forms.first else { continue }
            for form in forms.dropFirst() where form.count > 1 && result[form] == nil { result[form] = headword }
        }
        return result
    }
}

/// 문장 안 쓰임으로 품사 약어를 고른다 (번역 뜻에는 품사가 없다).
enum EnglishPartOfSpeech {
    private static let tagger = NLTagger(tagSchemes: [.lexicalClass])

    /// `meaning`(한국어 뜻)과 어긋나는 품사는 쓰지 않는다: 동사 뜻은 "-다"로 끝나고 명사 뜻은 그렇지 않다.
    static func abbreviation(of surface: String, in sentence: String, meaning: String) -> String? {
        guard !surface.isEmpty, !surface.contains(where: \.isWhitespace) else { return nil }
        let endsLikeVerb = meaning.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).hasSuffix("다")
        switch lexicalClass(of: surface, in: sentence) {
        case .noun: return endsLikeVerb ? nil : "n."
        case .verb: return endsLikeVerb ? "v." : nil
        case .adjective: return "adj."
        case .adverb: return endsLikeVerb ? nil : "adv."
        case .preposition: return endsLikeVerb ? nil : "prep."
        case .conjunction: return endsLikeVerb ? nil : "conj."
        case .pronoun: return endsLikeVerb ? nil : "pron."
        default: return nil
        }
    }

    /// 문장 속 쓰임만 본 품사 약어. 알 수 없으면 nil.
    static func abbreviation(of surface: String, in sentence: String) -> String? {
        guard !surface.isEmpty, !surface.contains(where: \.isWhitespace) else { return nil }
        switch lexicalClass(of: surface, in: sentence) {
        case .noun: return "n."
        case .verb: return "v."
        case .adjective: return "adj."
        case .adverb: return "adv."
        case .preposition: return "prep."
        case .conjunction: return "conj."
        case .pronoun: return "pron."
        default: return nil
        }
    }

    private static func lexicalClass(of surface: String, in sentence: String) -> NLTag? {
        let key = EnglishLemmatizer().normalize(surface)
        tagger.string = sentence
        tagger.setLanguage(.english, range: sentence.startIndex..<sentence.endIndex)
        var found: NLTag?
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation]
        ) { tag, range in
            guard EnglishLemmatizer().normalize(String(sentence[range])) == key else { return true }
            found = tag
            return false
        }
        return found
    }
}

/// 단어를 처음 누를 때 느리지 않게, 책을 열면 찾기에 쓰는 것들을 미리 준비한다.
/// - 기본 단어장과 위키낱말사전·예문(JSON, 합쳐 약 2MB) 읽기, lemma 모델 읽기, 번역 언어 팩 확인과 번역 세션 준비.
enum WordLookupWarmUp {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        Task {
            // 책 첫 화면이 먼저 그려지게 잠깐 기다린다.
            try? await Task.sleep(for: .milliseconds(600))
            _ = BundledWordIndex.shared
            _ = await Task.detached { WiktionaryDictionary.shared.words.count + EnglishWordForms.shared.count + AppMeaningExamples.shared.examples.count }.value
            _ = EnglishLemmatizer().lemmas(of: "arrived", in: "She arrived early.")
            _ = EnglishPartOfSpeech.abbreviation(of: "arrived", in: "She arrived early.", meaning: "도착하다")
            await TranslationWordLookupStep.warmUp()
        }
    }
}

/// 책 사전. `usesLemma`이면 원형 후보로 다시 찾는다.
struct GlossaryLookupStep: WordLookupStep {
    var usesLemma: Bool

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        let terms = usesLemma ? request.lemmas : [request.surface]
        guard let entry = terms.lazy.compactMap({ request.book.glossaryEntry(forSurface: $0) }).first else { return nil }
        return WordLookupResult(
            headword: entry.lemma.lowercased(),
            surface: request.surface,
            partOfSpeech: entry.partOfSpeech,
            meaning: entry.meaning,
            note: entry.note,
            toeicTag: nil,
            source: .bookGlossary
        )
    }
}

/// 앱에 들어 있는 기본 단어장(BundledWords.json)을 영어 철자로 찾는다. 본문 모양 → 원형 순서.
struct BundledPackLookupStep: WordLookupStep {
    var index: () -> [String: VocaWordJSON]

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        let words = index()
        guard let word = request.candidates.lazy.compactMap({ words[$0] }).first else { return nil }
        let note = word.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = word.toeicTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return WordLookupResult(
            headword: word.english.normalizedEnglish,
            surface: request.surface,
            partOfSpeech: nil,
            meaning: word.meaningKo,
            note: note.isEmpty ? nil : note,
            toeicTag: tag.isEmpty ? nil : tag,
            source: .bundledPack,
            examples: WordMeaningExample.whole(english: word.exampleEn, korean: word.exampleKo)
        )
    }
}

/// 기본 단어장을 한 번만 읽어 철자로 찾을 수 있게 둔다. 파일이 없으면 빈 사전.
enum BundledWordIndex {
    static let shared: [String: VocaWordJSON] = make((try? BundledWordPack.loadWords()) ?? [])

    static func make(_ words: [VocaWordJSON]) -> [String: VocaWordJSON] {
        Dictionary(words.map { ($0.english.normalizedEnglish, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Apple Intelligence(기기 안 모델)로 뜻을 만든다. 카드의 「⋯ → 기기에서 뜻 만들기」가 부른다.
/// 쓸 수 없으면 이유를 담아 `WordLookupStepFailure`를 던진다. 만든 뜻은 `store`에 남긴다.
struct GeneratedWordLookupStep: WordLookupStep {
    var generator: any EnglishWordGenerating
    var isEnabled: () -> Bool
    var store: GeneratedMeaningStore

    var progressMessage: String? { "기기 안에서 뜻을 만드는 중…" }

    /// 지금 쓸 수 없는 이유. nil이면 쓸 수 있다. 카드 메뉴가 항목을 끄고 짧은 이유를 보인다.
    var unavailableReason: EnglishWordGenerationUnavailableReason? {
        guard isEnabled() else { return .disabledInSettings }
        if case .unavailable(let reason) = generator.availability { return reason }
        return nil
    }

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        // 생성기는 활용형을 받아도 원형으로 돌려준다 (규칙 후보는 틀릴 수 있어 넘기지 않는다).
        let term = request.surface
        guard (try? EnglishWordInputValidator.validate(term)) != nil else {
            throw miss("영어 단어 하나만 만들 수 있어요.")
        }
        if let reason = unavailableReason {
            throw miss(reason.userMessage)
        }
        do {
            let generated = try await generator.generateWord(for: term)
            let draft = GeneratedWordDraftMapper.makeDraft(from: generated)
            let result = WordLookupResult(
                headword: generated.word,
                surface: request.surface,
                partOfSpeech: nil,
                meaning: draft.meaningKo,
                note: draft.note.isEmpty ? nil : draft.note,
                toeicTag: draft.toeicTag.isEmpty ? nil : draft.toeicTag,
                source: .generated,
                examples: WordMeaningExample.whole(english: draft.exampleEn, korean: draft.exampleKo)
            )
            store.save(result)
            return result
        } catch {
            throw miss((error as? LocalizedError)?.errorDescription ?? "기기 안에서 뜻을 만들지 못했어요.")
        }
    }

    private func miss(_ reason: String) -> WordLookupStepFailure {
        WordLookupStepFailure(miss: WordLookupMiss(message: reason))
    }
}

/// 전에 기기에서 만든 뜻을 본문 모양 → 원형 순서로 찾는다.
struct GeneratedMeaningLookupStep: WordLookupStep {
    var store: GeneratedMeaningStore

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        guard let stored = request.candidates.lazy.compactMap({ store.meaning(for: $0) }).first else { return nil }
        return WordLookupResult(
            headword: stored.headword,
            surface: request.surface,
            partOfSpeech: stored.partOfSpeech,
            meaning: stored.meaning,
            note: stored.note,
            toeicTag: stored.toeicTag,
            source: .generated,
            examples: stored.examples ?? []
        )
    }
}

/// 기기에서 만든 뜻을 남겨 두는 곳 (UserDefaults, 기기마다 따로). 본문 모양과 원형 둘 다로 찾을 수 있게 넣는다.
nonisolated final class GeneratedMeaningStore: @unchecked Sendable {
    nonisolated struct Stored: Codable, Hashable, Sendable {
        var headword: String
        var partOfSpeech: String?
        var meaning: String
        var note: String?
        var toeicTag: String?
        /// 예문을 남기기 전에 만든 뜻에는 없다.
        var examples: [WordMeaningExample]?
    }

    static let shared = GeneratedMeaningStore(defaults: .standard)
    static let defaultsKey = "readerGeneratedMeanings"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func meaning(for term: String) -> Stored? {
        lock.withLock { all()[term.lowercased()] }
    }

    func save(_ result: WordLookupResult) {
        let stored = Stored(
            headword: result.headword,
            partOfSpeech: result.partOfSpeech,
            meaning: result.meaning,
            note: result.note,
            toeicTag: result.toeicTag,
            examples: result.examples
        )
        lock.withLock {
            var map = all()
            for key in Set([result.surface.lowercased(), result.headword.lowercased()]) where !key.isEmpty {
                map[key] = stored
            }
            if let data = try? JSONEncoder().encode(map) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
        }
    }

    private func all() -> [String: Stored] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let map = try? JSONDecoder().decode([String: Stored].self, from: data)
        else { return [:] }
        return map
    }
}
