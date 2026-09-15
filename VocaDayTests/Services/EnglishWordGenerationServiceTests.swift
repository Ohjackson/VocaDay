import SwiftData
import XCTest
@testable import VocaDay

@MainActor
final class EnglishWordGenerationServiceTests: XCTestCase {
    func testInputValidationRejectsAnythingOtherThanOneEnglishWord() {
        let invalidInputs = ["", "   ", "hello world", "1234", "!@#$"]

        for input in invalidInputs {
            XCTAssertThrowsError(try EnglishWordInputValidator.validate(input), "입력: \(input)")
        }

        XCTAssertEqual(try EnglishWordInputValidator.validate("  Run  "), "run")
        XCTAssertEqual(try EnglishWordInputValidator.validate("well-known"), "well-known")
        XCTAssertEqual(try EnglishWordInputValidator.validate("don't"), "don't")
    }

    func testGeneratedResultValidationLimitsAndDeduplicatesMeanings() throws {
        let duplicated = GeneratedEnglishWord(
            word: "run",
            meanings: [
                meaning(.verb, "달리다", "I run every morning.", "나는 매일 아침 달린다."),
                meaning(.verb, "달리다", "We run after work.", "우리는 퇴근 후 달린다."),
                meaning(.verb, "운영하다", "She runs a shop.", "그녀는 가게를 운영한다.")
            ],
            usageNote: "동사로 자주 사용",
            toeicTag: "일상 표현",
            spellingCorrection: ""
        )

        let validated = try EnglishWordGenerationValidator.validate(duplicated, for: "running")
        XCTAssertEqual(validated.word, "run")
        XCTAssertEqual(validated.meanings.map(\.meaning), ["달리다", "운영하다"])

        let tooMany = GeneratedEnglishWord(
            word: "light",
            meanings: (0..<4).map { index in
                meaning(.noun, "뜻 \(index)", "This light is bright.", "이 빛은 밝다.")
            },
            usageNote: "빛을 나타냄",
            toeicTag: "일상 표현",
            spellingCorrection: ""
        )
        XCTAssertThrowsError(try EnglishWordGenerationValidator.validate(tooMany, for: "light"))

        let emptyExample = GeneratedEnglishWord(
            word: "issue",
            meanings: [meaning(.noun, "문제", "", "이 문제를 해결해야 한다.")],
            usageNote: "문제를 나타냄",
            toeicTag: "업무",
            spellingCorrection: ""
        )
        XCTAssertThrowsError(try EnglishWordGenerationValidator.validate(emptyExample, for: "issue"))
    }

    func testRunMapsMultiplePartsOfSpeechIntoExistingDraftFormat() {
        let generated = GeneratedEnglishWord(
            word: "run",
            meanings: [
                meaning(.verb, "달리다", "I run every morning.", "나는 매일 아침 달린다."),
                meaning(.verb, "운영하다", "She runs a small business.", "그녀는 작은 사업을 운영한다."),
                meaning(.noun, "달리기", "I went for a run after work.", "나는 퇴근 후 달리기를 하러 갔다.")
            ],
            usageNote: "run a business는 사업을 운영하다는 뜻",
            toeicTag: "일상·업무",
            spellingCorrection: ""
        )

        let draft = GeneratedWordDraftMapper.makeDraft(from: generated)

        XCTAssertEqual(draft.english, "run")
        XCTAssertEqual(draft.meaningKo, "v. 달리다, v. 운영하다, n. 달리기")
        XCTAssertTrue(draft.exampleEn.contains("1. I run every morning."))
        XCTAssertTrue(draft.exampleKo.contains("3. 나는 퇴근 후 달리기를 하러 갔다."))
        XCTAssertEqual(draft.note, "run a business는 사업을 운영하다는 뜻")
        XCTAssertEqual(draft.toeicTag, "일상·업무")
    }

    func testLikelyMisspellingMapsToCorrectedHeadwordAndNote() throws {
        let generated = GeneratedEnglishWord(
            word: "postpone",
            meanings: [
                meaning(
                    .verb,
                    "연기하다",
                    "The meeting has been postponed until next Monday.",
                    "회의가 다음 주 월요일까지 연기되었습니다."
                )
            ],
            usageNote: "postpone + 명사 또는 postpone ~ing 형태로 자주 사용됩니다.",
            toeicTag: "일정·회의",
            spellingCorrection: "‘postphone’은 잘못된 철자이며 올바른 철자는 ‘postpone’입니다."
        )

        let validated = try EnglishWordGenerationValidator.validate(generated, for: "postphone")
        let draft = GeneratedWordDraftMapper.makeDraft(from: validated)

        XCTAssertEqual(draft.english, "postpone")
        XCTAssertEqual(draft.meaningKo, "v. 연기하다")
        XCTAssertEqual(draft.exampleEn, "The meeting has been postponed until next Monday.")
        XCTAssertEqual(draft.exampleKo, "회의가 다음 주 월요일까지 연기되었습니다.")
        XCTAssertTrue(draft.note.contains("올바른 철자는 ‘postpone’"))
        XCTAssertEqual(draft.toeicTag, "일정·회의")
    }

    func testRequiredVocabularyFixturesPassGenerationContract() async throws {
        let fixtures: [GeneratedEnglishWord] = [
            word("run", .verb, "달리다"),
            word("light", .noun, "빛"),
            word("issue", .noun, "문제"),
            word("available", .adjective, "이용 가능한"),
            word("appropriate", .adjective, "적절한"),
            word("fund", .noun, "기금"),
            word("settle", .verb, "해결하다")
        ]
        let service = StubWordGenerationService(fixtures: fixtures)

        for expected in fixtures {
            let generated = try await service.generateWord(for: expected.word)
            let validated = try EnglishWordGenerationValidator.validate(generated, for: expected.word)
            let draft = GeneratedWordDraftMapper.makeDraft(from: validated)

            XCTAssertEqual(draft.english, expected.word)
            XCTAssertTrue((1...3).contains(validated.meanings.count))
            XCTAssertFalse(draft.meaningKo.isEmpty)
            XCTAssertFalse(draft.exampleEn.isEmpty)
            XCTAssertFalse(draft.exampleKo.isEmpty)
        }
    }

    func testLiveFoundationModelGeneratesRequiredVocabularyWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_FOUNDATION_MODELS_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("실제 온디바이스 모델 테스트는 명시적으로 활성화한 기기에서만 실행합니다.")
        }

        let service = AppleFoundationWordGenerationService()
        guard service.availability.isAvailable else {
            throw XCTSkip(service.availability.statusMessage)
        }

        let words = ["run", "light", "issue", "available", "appropriate", "fund", "settle"]
        for word in words {
            let result = try await service.generateWord(for: word)
            XCTAssertEqual(result.word, word)
            XCTAssertTrue((1...3).contains(result.meanings.count))
            XCTAssertTrue(result.meanings.allSatisfy {
                !$0.meaning.isEmpty && !$0.englishExample.isEmpty && !$0.koreanExample.isEmpty
            })
        }
    }

    func testLiveFoundationModelCorrectsPostphoneWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_FOUNDATION_MODELS_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("실제 온디바이스 모델 테스트는 명시적으로 활성화한 기기에서만 실행합니다.")
        }

        let service = AppleFoundationWordGenerationService()
        guard service.availability.isAvailable else {
            throw XCTSkip(service.availability.statusMessage)
        }

        let result = try await service.generateWord(for: "postphone")
        let draft = GeneratedWordDraftMapper.makeDraft(from: result)

        XCTAssertEqual(result.word, "postpone")
        XCTAssertEqual(draft.english, "postpone")
        XCTAssertTrue(
            draft.meaningKo.contains("연기") || draft.meaningKo.contains("미루"),
            "생성된 뜻: \(draft.meaningKo)"
        )
        XCTAssertTrue(draft.note.contains("postphone"), "생성된 메모: \(draft.note)")
        XCTAssertFalse(draft.exampleEn.isEmpty)
        XCTAssertFalse(draft.exampleKo.isEmpty)
        XCTAssertFalse(draft.toeicTag.isEmpty)
    }

    func testMappedDraftSavesWithoutChangingExistingSwiftDataSchema() throws {
        let container = try ModelContainer(
            for: VocabularyDay.self,
            VocaWord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let day = VocabularyDay(title: "Day 1")
        context.insert(day)

        let draft = GeneratedWordDraftMapper.makeDraft(
            from: word("available", .adjective, "이용 가능한")
        )
        let saved = GeneratedWordDraftMapper.makeEntity(
            from: draft,
            day: day,
            now: Date(timeIntervalSince1970: 100)
        )
        context.insert(saved)
        day.appendWord(saved)
        try context.save()

        let words = try context.fetch(FetchDescriptor<VocaWord>())
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.id, draft.id)
        XCTAssertEqual(words.first?.english, "available")
        XCTAssertEqual(words.first?.meaningKo, "adj. 이용 가능한")
        XCTAssertEqual(words.first?.reviewCount, 0)
        XCTAssertEqual(words.first?.status, WordStatus.new.rawValue)
        XCTAssertEqual(words.first?.day?.id, day.id)
    }

    private func meaning(
        _ partOfSpeech: GeneratedPartOfSpeech,
        _ definition: String,
        _ englishExample: String,
        _ koreanExample: String
    ) -> GeneratedWordMeaning {
        GeneratedWordMeaning(
            partOfSpeech: partOfSpeech,
            meaning: definition,
            englishExample: englishExample,
            koreanExample: koreanExample
        )
    }

    private func word(
        _ english: String,
        _ partOfSpeech: GeneratedPartOfSpeech,
        _ definition: String
    ) -> GeneratedEnglishWord {
        GeneratedEnglishWord(
            word: english,
            meanings: [
                meaning(
                    partOfSpeech,
                    definition,
                    "The word \(english) is used naturally here.",
                    "여기에서 \(english)이라는 단어가 자연스럽게 사용된다."
                )
            ],
            usageNote: "학습에 도움이 되는 사용 설명",
            toeicTag: "일상 표현",
            spellingCorrection: ""
        )
    }
}

private struct StubWordGenerationService: EnglishWordGenerating {
    let fixtures: [String: GeneratedEnglishWord]

    init(fixtures: [GeneratedEnglishWord]) {
        self.fixtures = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.word, $0) })
    }

    var availability: EnglishWordGenerationAvailability { .available }

    func generateWord(for input: String) async throws -> GeneratedEnglishWord {
        let word = try EnglishWordInputValidator.validate(input)
        guard let result = fixtures[word] else {
            throw EnglishWordGenerationError.unrelatedResponse
        }
        return result
    }
}
