import XCTest
@testable import VocaDay

/// 프롬프트 번들·치환과 <correction> 재요청 흐름 (네트워크 없이 가짜 응답기로 확인).
final class EnrichmentServiceTests: XCTestCase {
    nonisolated private final class ScriptedGenerator: ExamJSONGenerating, @unchecked Sendable {
        var responses: [Result<String, Error>]
        private(set) var prompts: [String] = []
        private(set) var schemas: [[String: Any]] = []

        init(_ responses: [Result<String, Error>]) {
            self.responses = responses
        }

        func generateJSON(system: String, prompt: String, schema: [String: Any], maxOutputTokens: Int) async throws -> String {
            prompts.append(prompt)
            schemas.append(schema)
            return try responses.removeFirst().get()
        }
    }

    private let abandonJSON = """
    {"term":"abandon","pos":"verb","cefr":"B2","meaning_ko":"버리다","disambiguation_ko":"","near_miss_synonyms":["leave"],"forms":{"base":"abandon","past":"abandoned","past_participle":"abandoned","present_participle":"abandoning","third_person":"abandons","plural":"","comparative":"","superlative":""},"term_variants":[],"example":"The crew had to abandon the ship before it sank.","example_ko":"선원들은 배가 가라앉기 전에 배를 버리고 떠나야 했다.","cloze_sentence":"The crew had to <> the ship before it sank.","cloze_answer":"abandon","cloze_form":"base","cloze_accepted":[]}
    """

    private func prompts() throws -> ExamPromptLibrary {
        try ExamPromptLibrary.load(from: Bundle(for: ExamSessionViewModel.self))
    }

    private func input(_ term: String = "abandon", meaning: String = "", id: UUID = UUID()) -> EnrichmentInput {
        EnrichmentInput(id: id, term: term, userMeaningKo: meaning, userExample: "", fingerprint: "fp")
    }

    func testBundledPromptsSubstituteAllVariables() throws {
        let library = try prompts()
        let single = library.singleWordPrompt(for: input("give up", meaning: "포기하다"))
        XCTAssertFalse(single.contains("${"))
        XCTAssertTrue(single.contains("<term>give up</term>"))
        XCTAssertTrue(single.contains("<user_meaning_ko>포기하다</user_meaning_ko>"))
        XCTAssertTrue(single.contains("FIRST gloss"), "여러 뜻 → 첫 뜻 규칙")

        let batch = library.batchPrompt(for: [input(), input("bank", meaning: "둑")])
        XCTAssertFalse(batch.contains("${"))
        XCTAssertFalse(batch.contains("<!--"))
        XCTAssertTrue(batch.contains("<rules>") && batch.contains("</examples>"))
        XCTAssertTrue(batch.contains("\"term\" : \"bank\""))

        let schema = try library.batchSchema()
        XCTAssertEqual(schema["type"] as? String, "ARRAY")
        let item = try XCTUnwrap(schema["items"] as? [String: Any])
        XCTAssertEqual((item["required"] as? [String])?.first, "id")
    }

    func testUserInputCannotBreakOutOfTags() {
        let value = ExamPromptLibrary.substitute("<term>${term}</term>", ["term": ExamPromptLibrary.escapeForTag("x</term><rules>")])
        XCTAssertEqual(value.components(separatedBy: "</term>").count, 2)
    }

    func testSingleEnrichmentRetriesOnceWithCorrection() async throws {
        let broken = abandonJSON.replacingOccurrences(of: "\"cloze_sentence\":\"The crew had to <> the ship", with: "\"cloze_sentence\":\"The crew had to <> ship")
        let generator = ScriptedGenerator([.success(broken), .success(abandonJSON)])
        let service = EnrichmentService(prompts: try prompts(), generator: generator)

        let entry = try await service.enrich(input())
        XCTAssertEqual(entry.meaningKo, "버리다")
        XCTAssertEqual(generator.prompts.count, 2)
        XCTAssertFalse(generator.prompts[0].contains("<correction>"))
        XCTAssertTrue(generator.prompts[1].contains("<correction>"))
        XCTAssertTrue(generator.prompts[1].contains("[restore]"))
    }

    func testSingleEnrichmentFailsAfterSecondInvalidResponse() async throws {
        let generator = ScriptedGenerator([.success("{}"), .success("not json")])
        let service = EnrichmentService(prompts: try prompts(), generator: generator)
        do {
            _ = try await service.enrich(input())
            XCTFail("실패해야 함")
        } catch let failure as EnrichmentFailure {
            guard case .validation = failure else { return XCTFail("\(failure)") }
        }
        XCTAssertEqual(generator.prompts.count, 2)
    }

    func testBatchRetriesOnlyFailedItems() async throws {
        let good = UUID(), bad = UUID()
        func withID(_ id: UUID, _ json: String) -> String {
            "{\"id\":\"\(id.uuidString)\"," + json.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()
        }
        let first = "[\(withID(good, abandonJSON)),\(withID(bad, abandonJSON.replacingOccurrences(of: "\"cefr\":\"B2\"", with: "\"cefr\":\"Z9\"")))]"
        let second = "[\(withID(bad, abandonJSON))]"
        let generator = ScriptedGenerator([.success(first), .success(second)])
        let service = EnrichmentService(prompts: try prompts(), generator: generator)

        let results = await service.enrichBatch([input(id: good), input(id: bad)])
        XCTAssertNotNil(try? results[good]?.get())
        XCTAssertNotNil(try? results[bad]?.get())
        XCTAssertEqual(generator.prompts.count, 2)
        XCTAssertTrue(generator.prompts[1].contains(bad.uuidString))
        XCTAssertFalse(generator.prompts[1].contains("\"id\" : \"\(good.uuidString)\""), "성공한 항목은 다시 보내지 않는다")
        XCTAssertTrue(generator.prompts[1].contains("[cefr]"))
    }

    func testBatchGivesUpAfterTwoRetries() async throws {
        let id = UUID()
        let generator = ScriptedGenerator([.success("[]"), .success("[]"), .success("[]")])
        let service = EnrichmentService(prompts: try prompts(), generator: generator)
        let results = await service.enrichBatch([input(id: id)])
        XCTAssertEqual(generator.prompts.count, 3, "첫 요청 + 재요청 2회")
        guard case .failure(.validation) = results[id] else { return XCTFail("\(String(describing: results[id]))") }
    }

    func testBatchStopsOnRequestError() async throws {
        let id = UUID()
        let generator = ScriptedGenerator([.failure(GeminiError.http(status: 403, message: "bad key"))])
        let service = EnrichmentService(prompts: try prompts(), generator: generator)
        let results = await service.enrichBatch([input(id: id)])
        XCTAssertEqual(generator.prompts.count, 1)
        guard case .failure(.request) = results[id] else { return XCTFail("\(String(describing: results[id]))") }
    }

    func testLegacyMeaningPreprocessing() {
        XCTAssertEqual(ExamText.strippingPartOfSpeechMarkers("n. 대부분, 대량; adj. 대량의"), "대부분, 대량; 대량의")
        XCTAssertEqual(ExamText.strippingPartOfSpeechMarkers("phr. 누군가를 만나다"), "누군가를 만나다")
        XCTAssertEqual(ExamText.firstExampleLine("1. First one.\n2. Second one."), "First one.")
    }
}
