import Foundation

// 리더 단어 찾기의 언어 공통 부분. 언어마다 원형 만들기(`WordLemmatizing`)와 찾기 단계(`WordLookupStep`)만 바꿔 끼운다.
// 영어 단계는 EnglishWordLookup.swift. 일본어 앱은 형태소·읽기를 다루는 단계로 바꾼다.

/// 뜻을 어디서 찾았는지. 카드에 출처로 보여 준다.
nonisolated enum WordLookupSource: String, Hashable, Sendable {
    case bookGlossary
    case bundledPack
    case generated

    var label: String {
        switch self {
        case .bookGlossary: "책 사전"
        case .bundledPack: "기본 단어장"
        case .generated: "기기 안 생성"
        }
    }

    var systemImage: String {
        switch self {
        case .bookGlossary: "book.closed"
        case .bundledPack: "text.book.closed"
        case .generated: "sparkles"
        }
    }
}

/// 찾기 한 번의 입력. 원형 후보는 파이프라인이 한 번만 만들어 모든 단계에 넘긴다.
nonisolated struct WordLookupRequest: Hashable, Sendable {
    /// 본문 모양을 다듬은 값 (앞뒤 문장부호·소유격 제거, 소문자). 예: "allocated"
    var surface: String
    /// 원형 후보, 그럴듯한 순서. 본문 모양은 넣지 않는다. 예: ["allocate"]
    var lemmas: [String]
    var sentence: String
    var book: BookDocument

    var lemma: String? { lemmas.first }

    /// 본문 모양 다음 원형 후보 순서. 겹치면 하나만.
    var candidates: [String] {
        ([surface] + lemmas).reduce(into: []) { result, term in
            if !term.isEmpty, !result.contains(term) { result.append(term) }
        }
    }
}

/// 찾은 뜻 한 개.
nonisolated struct WordLookupResult: Hashable, Sendable {
    /// 단어장에 넣을 표제어 (원형). 예: "allocate"
    var headword: String
    /// 본문에 나온 모양. 예: "allocated"
    var surface: String
    /// 예: "v." 뜻에 품사가 이미 들어 있으면 nil.
    var partOfSpeech: String?
    /// 한국어 뜻. 예: "할당하다, 배정하다"
    var meaning: String
    var note: String?
    var toeicTag: String?
    var source: WordLookupSource

    /// 원형이 본문 모양과 달라 카드에 따로 보여 줄지.
    var showsLemma: Bool { headword.lowercased() != surface.lowercased() }

    /// 단어장에 저장하는 뜻. 품사 약어를 앞에 붙인다 (기존 단어 형식: "v. 할당하다").
    var meaningForSaving: String {
        guard let partOfSpeech, !partOfSpeech.isEmpty else { return meaning }
        return "\(partOfSpeech) \(meaning)"
    }
}

/// 마지막 단계까지 찾지 못했을 때 카드에 보여 줄 내용.
nonisolated struct WordLookupMiss: Hashable, Sendable {
    /// 못 찾은 이유 한두 문장.
    var message: String
    /// 기기 안 생성을 쓰려면 사용자의 동의가 먼저 필요하다. 카드가 동의 버튼을 보여 준다.
    var needsGenerationConsent = false
}

nonisolated enum WordLookupOutcome: Hashable, Sendable {
    case found(WordLookupResult)
    case notFound(WordLookupMiss)
}

/// 단계가 "못 찾음" 대신 이유를 남기고 싶을 때 던진다. 파이프라인은 다음 단계로 넘어가고, 끝까지 못 찾으면 마지막 이유를 쓴다.
nonisolated struct WordLookupStepFailure: Error, Hashable, Sendable {
    var miss: WordLookupMiss
}

/// 원형 만들기. 언어마다 다르다 (영어 `NLTagger` lemma, 일본어는 형태소 분석).
protocol WordLemmatizing {
    /// `sentence` 안에서 `surface`의 원형 후보, 그럴듯한 순서. 문장 속 쓰임을 보고 품사를 가린다.
    func lemmas(of surface: String, in sentence: String) -> [String]
    /// 누른 모양을 찾기 좋게 다듬는다.
    func normalize(_ surface: String) -> String
}

/// 찾기 한 단계. 못 찾으면 nil, 이유를 남기려면 `WordLookupStepFailure`.
protocol WordLookupStep {
    /// 시간이 걸리는 단계면 카드가 기다리는 문구를 바꾼다.
    var progressMessage: String? { get }
    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult?
}

extension WordLookupStep {
    var progressMessage: String? { nil }
}

/// 단계를 순서대로 돌려 처음 찾은 뜻을 쓴다.
struct WordLookupPipeline {
    var lemmatizer: any WordLemmatizing
    var steps: [any WordLookupStep]
    /// 끝까지 못 찾았을 때의 설명. 카드 제목("뜻을 찾지 못했어요") 아래에 보인다.
    var notFoundMessage = "책 사전과 기본 단어장에 없는 단어예요."

    func request(for context: WordTapContext, book: BookDocument) -> WordLookupRequest {
        let surface = lemmatizer.normalize(context.surface)
        let lemmas = lemmatizer.lemmas(of: surface, in: context.sentence)
            .map { $0.lowercased() }
            .reduce(into: [String]()) { result, lemma in
                if !lemma.isEmpty, lemma != surface, !result.contains(lemma) { result.append(lemma) }
            }
        return WordLookupRequest(surface: surface, lemmas: lemmas, sentence: context.sentence, book: book)
    }

    func lookup(
        _ context: WordTapContext,
        book: BookDocument,
        progress: (String) -> Void = { _ in }
    ) async -> WordLookupOutcome {
        await lookup(request(for: context, book: book), progress: progress)
    }

    func lookup(_ request: WordLookupRequest, progress: (String) -> Void = { _ in }) async -> WordLookupOutcome {
        guard !request.surface.isEmpty else {
            return .notFound(WordLookupMiss(message: notFoundMessage))
        }
        var lastMiss: WordLookupMiss?
        for step in steps {
            if let message = step.progressMessage { progress(message) }
            do {
                if let result = try await step.lookup(request) {
                    return .found(result)
                }
            } catch let failure as WordLookupStepFailure {
                lastMiss = failure.miss
            } catch {
                lastMiss = WordLookupMiss(message: notFoundMessage)
            }
        }
        return .notFound(lastMiss ?? WordLookupMiss(message: notFoundMessage))
    }
}
