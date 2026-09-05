import Foundation
import FoundationModels

@Generable(description: "A common modern part of speech for an English word meaning.")
enum GeneratedPartOfSpeech: Sendable, Equatable, CaseIterable {
    case noun
    case verb
    case adjective
    case adverb
    case preposition
    case conjunction
    case pronoun
    case interjection
    case other

    var koreanName: String {
        switch self {
        case .noun: "명사"
        case .verb: "동사"
        case .adjective: "형용사"
        case .adverb: "부사"
        case .preposition: "전치사"
        case .conjunction: "접속사"
        case .pronoun: "대명사"
        case .interjection: "감탄사"
        case .other: "기타"
        }
    }
}

@Generable(description: "One common meaning of an English word for a Korean learner.")
struct GeneratedWordMeaning: Sendable, Equatable {
    @Guide(description: "The part of speech for this exact meaning.")
    var partOfSpeech: GeneratedPartOfSpeech

    @Guide(description: "A concise and natural Korean dictionary definition.")
    var meaning: String

    @Guide(description: "A short natural English sentence that clearly uses this exact meaning.")
    var englishExample: String

    @Guide(description: "A natural Korean translation of the English example sentence.")
    var koreanExample: String
}

@Generable(description: "A dictionary-style analysis containing only the most common modern meanings of one English word.")
struct GeneratedEnglishWord: Sendable, Equatable {
    @Guide(description: "The lowercase dictionary headword or lemma for the user's English word.")
    var word: String

    @Guide(
        description: "Between one and three distinct meanings ordered by real-world usage frequency.",
        .count(1...3)
    )
    var meanings: [GeneratedWordMeaning]
}

enum EnglishWordGenerationUnavailableReason: Sendable, Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    var userMessage: String {
        switch self {
        case .deviceNotEligible:
            "이 기기는 Apple Intelligence를 지원하지 않습니다. iPhone에서는 15 Pro·15 Pro Max 및 이후 Apple Intelligence 지원 모델에서 사용할 수 있으며, 지원되지 않는 기기에서는 수동으로 뜻과 예문을 입력할 수 있어요."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence가 꺼져 있습니다. 시스템 설정에서 켜거나 직접 추가를 사용하세요."
        case .modelNotReady:
            "온디바이스 모델이 아직 준비되지 않았습니다. 잠시 후 다시 시도하거나 직접 추가를 사용하세요."
        }
    }
}

enum EnglishWordGenerationAvailability: Sendable, Equatable {
    case available
    case unavailable(EnglishWordGenerationUnavailableReason)

    var isAvailable: Bool {
        self == .available
    }

    var statusMessage: String {
        switch self {
        case .available:
            "Apple Intelligence가 기기 안에서 뜻과 예문을 생성하며, 입력한 단어는 외부 AI 서비스로 전송되지 않습니다."
        case .unavailable(let reason):
            reason.userMessage
        }
    }
}

enum EnglishWordGenerationError: LocalizedError, Equatable {
    case emptyInput
    case multipleWords
    case invalidCharacters
    case unavailable(EnglishWordGenerationUnavailableReason)
    case unrelatedResponse
    case invalidResponse(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "영단어를 입력하세요."
        case .multipleWords:
            "한 번에 영어 단어 하나만 입력하세요. 띄어쓰기가 포함된 문장은 지원하지 않습니다."
        case .invalidCharacters:
            "영문자와 단어 안의 하이픈 또는 아포스트로피만 사용할 수 있습니다."
        case .unavailable(let reason):
            reason.userMessage
        case .unrelatedResponse:
            "입력한 단어와 관련 없는 결과가 생성되었습니다. 다시 시도해 주세요."
        case .invalidResponse(let message):
            message
        case .generationFailed:
            "학습 데이터를 생성하지 못했습니다. 다시 시도하거나 직접 추가를 사용하세요."
        }
    }
}

enum EnglishWordInputValidator {
    static func validate(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EnglishWordGenerationError.emptyInput
        }
        guard !trimmed.contains(where: { $0.isWhitespace }) else {
            throw EnglishWordGenerationError.multipleWords
        }

        let pattern = #"^[A-Za-z]+(?:['’\-][A-Za-z]+)*$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw EnglishWordGenerationError.invalidCharacters
        }
        return trimmed.lowercased()
    }
}

protocol EnglishWordGenerating: Sendable {
    var availability: EnglishWordGenerationAvailability { get }
    func generateWord(for input: String) async throws -> GeneratedEnglishWord
}

struct AppleFoundationWordGenerationService: EnglishWordGenerating {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var availability: EnglishWordGenerationAvailability {
        switch model.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            .unavailable(.modelNotReady)
        }
    }

    func generateWord(for input: String) async throws -> GeneratedEnglishWord {
        let word = try EnglishWordInputValidator.validate(input)
        guard case .available = availability else {
            if case .unavailable(let reason) = availability {
                throw EnglishWordGenerationError.unavailable(reason)
            }
            throw EnglishWordGenerationError.unavailable(.modelNotReady)
        }

        let session = LanguageModelSession(model: model, instructions: Self.instructions)

        do {
            let response = try await session.respond(
                to: "Analyze this single English word: \(word)",
                generating: GeneratedEnglishWord.self,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 700)
            )
            return try EnglishWordGenerationValidator.validate(response.content, for: word)
        } catch let error as EnglishWordGenerationError {
            throw error
        } catch {
            throw EnglishWordGenerationError.generationFailed(error.localizedDescription)
        }
    }

    private static let instructions = """
    You are an English-Korean dictionary assistant for Korean learners.

    Analyze only the single English word provided by the user.

    Rules:
    - Return the lowercase dictionary headword or lemma.
    - Return only modern and commonly used meanings.
    - Select meanings primarily by actual usage frequency.
    - Return between 1 and 3 meanings.
    - Do not add rare, archaic, technical, or overly specialized meanings just to fill the list.
    - Distinguish the part of speech for each meaning.
    - Each meaning must have one short, natural English example sentence.
    - Each example must clearly demonstrate that exact meaning.
    - Provide a natural Korean translation of every example.
    - Korean definitions must be concise dictionary-style expressions.
    - Avoid duplicate or nearly identical meanings.
    - Prefer situations useful in everyday life or ordinary work.
    """
}

enum EnglishWordGenerationValidator {
    static func validate(_ result: GeneratedEnglishWord, for input: String) throws -> GeneratedEnglishWord {
        let normalizedInput = try EnglishWordInputValidator.validate(input)
        let generatedWord = try EnglishWordInputValidator.validate(result.word)

        guard wordsAreRelated(input: normalizedInput, generated: generatedWord) else {
            throw EnglishWordGenerationError.unrelatedResponse
        }
        guard (1...3).contains(result.meanings.count) else {
            throw EnglishWordGenerationError.invalidResponse("일반적인 뜻을 1개에서 3개 사이로 생성하지 못했습니다.")
        }

        var seenMeanings: Set<String> = []
        var validatedMeanings: [GeneratedWordMeaning] = []

        for meaning in result.meanings {
            let definition = meaning.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            let englishExample = meaning.englishExample.trimmingCharacters(in: .whitespacesAndNewlines)
            let koreanExample = meaning.koreanExample.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !definition.isEmpty, !englishExample.isEmpty, !koreanExample.isEmpty else {
                throw EnglishWordGenerationError.invalidResponse("뜻과 영어·한국어 예문이 모두 포함된 결과를 만들지 못했습니다.")
            }

            let duplicateKey = definition.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "ko_KR")
            )
            guard seenMeanings.insert(duplicateKey).inserted else { continue }

            validatedMeanings.append(
                GeneratedWordMeaning(
                    partOfSpeech: meaning.partOfSpeech,
                    meaning: definition,
                    englishExample: englishExample,
                    koreanExample: koreanExample
                )
            )
        }

        guard !validatedMeanings.isEmpty else {
            throw EnglishWordGenerationError.invalidResponse("서로 다른 일반적인 뜻을 생성하지 못했습니다.")
        }

        return GeneratedEnglishWord(word: generatedWord, meanings: validatedMeanings)
    }

    private static func wordsAreRelated(input: String, generated: String) -> Bool {
        guard input != generated else { return true }

        let simpleSuffixes = ["s", "es", "ed", "ing", "er", "est"]
        if simpleSuffixes.contains(where: { input == generated + $0 || generated == input + $0 }) {
            return true
        }

        if input.hasSuffix("ing") {
            let stem = String(input.dropLast(3))
            if stem == generated || String(stem.dropLast()) == generated || stem + "e" == generated {
                return true
            }
        }

        if input.hasSuffix("ed") {
            let stem = String(input.dropLast(2))
            if stem == generated || String(stem.dropLast()) == generated || stem + "e" == generated {
                return true
            }
        }

        return false
    }
}

enum GeneratedWordDraftMapper {
    static func makeDraft(from generated: GeneratedEnglishWord, id: UUID = UUID()) -> VocaWordJSON {
        let meanings = generated.meanings
        let meaningText = meanings
            .map { "\($0.partOfSpeech.koreanName) · \($0.meaning)" }
            .joined(separator: "\n")
        let englishExamples = numberedLines(meanings.map(\.englishExample))
        let koreanExamples = numberedLines(meanings.map(\.koreanExample))
        let partOfSpeechNames = meanings.reduce(into: [String]()) { names, meaning in
            let name = meaning.partOfSpeech.koreanName
            if !names.contains(name) {
                names.append(name)
            }
        }

        return VocaWordJSON(
            id: id,
            english: generated.word,
            meaningKo: meaningText,
            exampleEn: englishExamples,
            exampleKo: koreanExamples,
            note: "",
            toeicTag: partOfSpeechNames.joined(separator: " · ")
        )
    }

    static func makeEntity(from draft: VocaWordJSON, day: VocabularyDay, now: Date = Date()) -> VocaWord {
        VocaWord(
            id: draft.id,
            english: draft.english,
            meaningKo: draft.meaningKo,
            exampleEn: draft.exampleEn,
            exampleKo: draft.exampleKo,
            note: draft.note,
            toeicTag: draft.toeicTag,
            createdAt: now,
            nextReviewAt: now,
            day: day
        )
    }

    private static func numberedLines(_ lines: [String]) -> String {
        guard lines.count > 1 else { return lines.first ?? "" }
        return lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}
