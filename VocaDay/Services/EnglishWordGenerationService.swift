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

    var abbreviation: String {
        switch self {
        case .noun: "n."
        case .verb: "v."
        case .adjective: "adj."
        case .adverb: "adv."
        case .preposition: "prep."
        case .conjunction: "conj."
        case .pronoun: "pron."
        case .interjection: "interj."
        case .other: "기타"
        }
    }
}

@Generable(description: "One common meaning of an English word for a Korean learner.")
struct GeneratedWordMeaning: Sendable, Equatable {
    @Guide(description: "The part of speech for this exact meaning.")
    var partOfSpeech: GeneratedPartOfSpeech

    @Guide(description: "반드시 한글로 작성한 간결하고 자연스러운 한국어 사전식 뜻.")
    var meaning: String

    @Guide(description: "A short natural English sentence that clearly uses this exact meaning.")
    var englishExample: String

    @Guide(description: "반드시 한글로 작성한 영어 예문의 자연스러운 한국어 번역.")
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

    @Guide(description: "반드시 한글로 작성한 문법이나 자주 쓰는 형태 중심의 짧은 암기 메모.")
    var usageNote: String

    @Guide(description: "반드시 한글로 작성한 짧은 TOEIC 또는 일상 활용 분류. 예: 일정·회의, 일상 표현.")
    var toeicTag: String

    @Guide(description: "오타라면 반드시 한글로 작성한 철자 교정 설명. 철자가 맞으면 빈 문자열.")
    var spellingCorrection: String
}

@Generable(description: "A spelling resolution for one English word entered by a learner.")
private struct GeneratedWordSpellingResolution: Sendable {
    @Guide(description: "The lowercase, correctly spelled, common English dictionary headword. Correct a likely typo instead of inventing a meaning for a nonword.")
    var headword: String
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
        @unknown default:
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

        do {
            let resolvedHeadword = try await resolveHeadword(for: word)
            var request = "영단어 \(resolvedHeadword)의 한국어 학습 데이터를 생성하세요. word는 반드시 \(resolvedHeadword)로 반환하세요."
            var lastValidationError: EnglishWordGenerationError?

            for attempt in 0..<2 {
                let session = LanguageModelSession(model: model, instructions: Self.instructions)
                let response = try await session.respond(
                    to: request,
                    generating: GeneratedEnglishWord.self,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 700)
                )

                do {
                    var content = response.content
                    content.word = resolvedHeadword
                    content.spellingCorrection = word == resolvedHeadword
                        ? ""
                        : "‘\(word)’은 잘못된 철자이며 올바른 철자는 ‘\(resolvedHeadword)’입니다."
                    return try EnglishWordGenerationValidator.validate(content, for: word)
                } catch let error as EnglishWordGenerationError {
                    lastValidationError = error
                    guard attempt == 0 else { throw error }
                    request = """
                    영단어 \(resolvedHeadword)의 학습 데이터를 다시 생성하세요. word는 반드시 \(resolvedHeadword)로 반환하세요.
                    뜻, 예문 번역, 암기 메모, 활용 분류, 철자 교정 설명은 반드시 자연스러운 한글로 쓰세요. 한국어 뜻 자리에 영어 정의를 쓰면 안 됩니다.
                    \(resolvedHeadword) 자체에 실제로 존재하는 뜻과 품사만 포함하고 파생어나 관련 단어의 품사는 제외하세요.
                    """
                }
            }

            throw lastValidationError ?? EnglishWordGenerationError.invalidResponse("올바른 한국어 학습 데이터를 만들지 못했습니다.")
        } catch let error as EnglishWordGenerationError {
            throw error
        } catch {
            throw EnglishWordGenerationError.generationFailed(error.localizedDescription)
        }
    }

    private func resolveHeadword(for input: String) async throws -> String {
        let instructions = """
        You are a strict English spelling corrector for a dictionary app.
        Return one lowercase modern English dictionary headword.
        Correct a likely typo to the intended common word; never invent a definition for a nonword.
        Preserve a correctly spelled word.
        Examples: postphone becomes postpone; recieve becomes receive; run remains run.
        """
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: "Resolve this learner input to the intended correctly spelled headword: \(input)",
            generating: GeneratedWordSpellingResolution.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 80)
        )
        return try EnglishWordInputValidator.validate(response.content.headword)
    }

    private static let instructions = """
    당신은 한국인 영어 학습자를 위한 영한사전 도우미입니다. 사용자가 제공한 영단어 하나만 분석하세요.

    규칙:
    - 소문자 사전 표제어 원형을 반환합니다.
    - 먼저 입력이 흔한 영단어의 오타인지 판단합니다.
    - 오타이면 올바른 흔한 표제어로 교정하고 철자 교정 이유를 한국어로 짧게 씁니다.
    - 오타를 접미사나 단어 조각으로 오해해 뜻을 지어내지 않습니다.
    - 현대 영어에서 자주 쓰는 뜻만 실제 사용 빈도순으로 1~3개 반환합니다.
    - 개수를 채우려고 희귀하거나 낡았거나 전문적인 뜻을 추가하지 않습니다.
    - 각 뜻의 품사를 구분하되 반환한 표제어 자체에 존재하는 품사만 사용합니다. 파생어의 품사를 넣지 않습니다.
    - 각 뜻마다 그 의미가 분명한 짧고 자연스러운 영어 예문 하나를 만듭니다.
    - 뜻, 한국어 예문 번역, 암기 메모, 활용 분류, 철자 교정 설명은 반드시 한글이 포함된 자연스러운 한국어로 작성합니다. 영어 정의를 한국어 필드에 쓰지 않습니다.
    - 한국어 뜻은 간결한 사전식 표현으로 쓰고 사실상 같은 뜻은 중복하지 않습니다.
    - 일상이나 일반 업무에서 유용한 상황을 우선합니다.
    - 자주 쓰는 문법이나 결합 형태를 담은 한국어 암기 메모를 하나 씁니다.
    - 품사 대신 일정·회의 같은 짧고 실용적인 한국어 분류를 하나 씁니다.
    """
}

enum EnglishWordGenerationValidator {
    static func validate(_ result: GeneratedEnglishWord, for input: String) throws -> GeneratedEnglishWord {
        let normalizedInput = try EnglishWordInputValidator.validate(input)
        let generatedWord = try EnglishWordInputValidator.validate(result.word)
        let modelSpellingCorrection = result.spellingCorrection.trimmingCharacters(in: .whitespacesAndNewlines)

        guard wordsAreRelated(input: normalizedInput, generated: generatedWord) else {
            throw EnglishWordGenerationError.unrelatedResponse
        }
        guard normalizedInput == generatedWord
                || isCommonInflection(normalizedInput, of: generatedWord)
                || !modelSpellingCorrection.isEmpty else {
            throw EnglishWordGenerationError.invalidResponse("철자를 바꾼 이유를 설명하지 못했습니다. 다시 시도해 주세요.")
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
            guard containsHangul(definition), containsHangul(koreanExample) else {
                throw EnglishWordGenerationError.invalidResponse("한국어 뜻과 예문 번역을 생성하지 못했습니다.")
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

        let usageNote = result.usageNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let toeicTag = result.toeicTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let spellingCorrection: String
        if normalizedInput != generatedWord, !isCommonInflection(normalizedInput, of: generatedWord) {
            let canonicalCorrection = "‘\(normalizedInput)’은 잘못된 철자이며 올바른 철자는 ‘\(generatedWord)’입니다."
            spellingCorrection = modelSpellingCorrection.contains(normalizedInput)
                ? modelSpellingCorrection
                : canonicalCorrection
        } else {
            spellingCorrection = ""
        }
        guard !usageNote.isEmpty, !toeicTag.isEmpty else {
            throw EnglishWordGenerationError.invalidResponse("암기 메모와 활용 분류를 생성하지 못했습니다.")
        }
        guard containsHangul(usageNote), containsHangul(toeicTag) else {
            throw EnglishWordGenerationError.invalidResponse("한국어 암기 메모와 활용 분류를 생성하지 못했습니다.")
        }

        return GeneratedEnglishWord(
            word: generatedWord,
            meanings: validatedMeanings,
            usageNote: usageNote,
            toeicTag: toeicTag,
            spellingCorrection: spellingCorrection
        )
    }

    private static func wordsAreRelated(input: String, generated: String) -> Bool {
        guard input != generated else { return true }

        if isCommonInflection(input, of: generated) {
            return true
        }

        return min(input.count, generated.count) >= 5 && editDistance(input, generated) <= 2
    }

    private static func isCommonInflection(_ input: String, of generated: String) -> Bool {
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

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? max(left.count, right.count)
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
                || (0x3131...0x318E).contains(scalar.value)
                || (0x1100...0x11FF).contains(scalar.value)
        }
    }
}

enum GeneratedWordDraftMapper {
    static func makeDraft(from generated: GeneratedEnglishWord, id: UUID = UUID()) -> VocaWordJSON {
        let meanings = generated.meanings
        let meaningText = meanings
            .map { "\($0.partOfSpeech.abbreviation) \($0.meaning)" }
            .joined(separator: ", ")
        let englishExamples = numberedLines(meanings.map(\.englishExample))
        let koreanExamples = numberedLines(meanings.map(\.koreanExample))
        return VocaWordJSON(
            id: id,
            english: generated.word,
            meaningKo: meaningText,
            exampleEn: englishExamples,
            exampleKo: koreanExamples,
            note: [generated.spellingCorrection, generated.usageNote]
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            toeicTag: generated.toeicTag
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
