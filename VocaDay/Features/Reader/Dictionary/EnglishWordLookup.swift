import Foundation
import NaturalLanguage

// 영어 찾기 단계: 책 사전 → 원형으로 책 사전 → 기본 단어장 → 기기 안 생성.

enum EnglishWordLookup {
    /// `hasGenerationConsent`, `isGenerationEnabled`는 단어 추가 화면과 같은 설정 값을 읽는다.
    static func pipeline(
        bundledWords: @escaping () -> [String: VocaWordJSON] = { BundledWordIndex.shared },
        generator: any EnglishWordGenerating = AppleFoundationWordGenerationService(),
        isGenerationEnabled: @escaping () -> Bool = { GenerationSettings.isEnabled },
        hasGenerationConsent: @escaping () -> Bool = { GenerationSettings.hasConsent }
    ) -> WordLookupPipeline {
        WordLookupPipeline(
            lemmatizer: EnglishLemmatizer(),
            steps: [
                GlossaryLookupStep(usesLemma: false),
                GlossaryLookupStep(usesLemma: true),
                BundledPackLookupStep(index: bundledWords),
                GeneratedWordLookupStep(
                    generator: generator,
                    isEnabled: isGenerationEnabled,
                    hasConsent: hasGenerationConsent
                ),
            ]
        )
    }

    /// 단어 추가 화면(`AddWordsView`)과 같은 키.
    enum GenerationSettings {
        static let enabledKey = "isAppleIntelligenceWordGenerationEnabled"
        static let consentKey = "hasAcknowledgedAppleIntelligenceWordGeneration"

        static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        static var hasConsent: Bool { UserDefaults.standard.bool(forKey: consentKey) }
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

    /// `NLTagger` lemma가 먼저, 그다음 규칙 변화(-s, -ed, -ing …)를 되돌린 후보.
    /// lemma 모델이 없는 환경(iOS 시뮬레이터 등)에서는 tagger가 nil을 주므로 규칙 후보로 찾는다.
    func lemmas(of surface: String, in sentence: String) -> [String] {
        let key = normalize(surface)
        guard !key.isEmpty else { return [] }
        let tagged = lemma(matching: key, in: sentence) ?? lemma(matching: key, in: key)
        return ([tagged].compactMap { $0 } + Self.ruleLemmas(of: key)).filter { $0 != key }
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

    private func lemma(matching key: String, in text: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
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
            source: .bundledPack
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

/// Apple Intelligence(기기 안 모델)로 뜻을 만든다. 쓸 수 없으면 이유를 남긴다.
struct GeneratedWordLookupStep: WordLookupStep {
    var generator: any EnglishWordGenerating
    var isEnabled: () -> Bool
    var hasConsent: () -> Bool

    var progressMessage: String? { "기기 안에서 뜻을 만드는 중…" }

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        // 생성기는 활용형을 받아도 원형으로 돌려준다 (규칙 후보는 틀릴 수 있어 넘기지 않는다).
        let term = request.surface
        guard (try? EnglishWordInputValidator.validate(term)) != nil else { return nil }
        guard isEnabled() else {
            throw miss(EnglishWordGenerationUnavailableReason.disabledInSettings.userMessage)
        }
        if case .unavailable(let reason) = generator.availability {
            throw miss(reason.userMessage)
        }
        guard hasConsent() else {
            throw WordLookupStepFailure(miss: WordLookupMiss(
                message: "Apple Intelligence로 기기 안에서 뜻을 만들 수 있어요. 단어는 외부 AI 서비스로 보내지 않아요.",
                needsGenerationConsent: true
            ))
        }
        do {
            let generated = try await generator.generateWord(for: term)
            let draft = GeneratedWordDraftMapper.makeDraft(from: generated)
            return WordLookupResult(
                headword: generated.word,
                surface: request.surface,
                partOfSpeech: nil,
                meaning: draft.meaningKo,
                note: draft.note.isEmpty ? nil : draft.note,
                toeicTag: draft.toeicTag.isEmpty ? nil : draft.toeicTag,
                source: .generated
            )
        } catch {
            throw miss((error as? LocalizedError)?.errorDescription ?? "기기 안에서 뜻을 만들지 못했어요.")
        }
    }

    private func miss(_ reason: String) -> WordLookupStepFailure {
        WordLookupStepFailure(miss: WordLookupMiss(message: "책 사전과 기본 단어장에 없는 단어예요. \(reason)"))
    }
}
