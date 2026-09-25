import Foundation

nonisolated protocol ExamJSONGenerating: Sendable {
    func generateJSON(system: String, prompt: String, schema: [String: Any], maxOutputTokens: Int) async throws -> String
}

extension GeminiClient: ExamJSONGenerating {
    func generateJSON(system: String, prompt: String, schema: [String: Any], maxOutputTokens: Int) async throws -> String {
        try await generateJSON(system: system, prompt: prompt, schema: schema, maxOutputTokens: maxOutputTokens, timeout: 90)
    }
}

nonisolated enum EnrichmentFailure: Error, Equatable, LocalizedError {
    case validation([EntryValidationError])
    case request(String)

    var errorDescription: String? {
        switch self {
        case .validation(let errors):
            "AI 응답이 검증을 통과하지 못했습니다: \(errors.map(\.code).joined(separator: ", "))"
        case .request(let message):
            message
        }
    }
}

/// 단어 보강 (SPEC §6). 검증 실패 시 <correction> 블록을 붙여 다시 요청한다.
nonisolated struct EnrichmentService: Sendable {
    static let enrichmentVersion = 1
    static let batchSize = 10
    /// 일괄 보강에서 실패 항목을 다시 넣는 최대 횟수 (SPEC §6.2).
    static let batchRetryLimit = 2

    let prompts: ExamPromptLibrary
    let generator: any ExamJSONGenerating

    // MARK: 단어 1개 (SPEC §6.1)

    func enrich(_ input: EnrichmentInput) async throws -> WordEntry {
        let prompt = prompts.singleWordPrompt(for: input)
        do {
            return try await requestSingle(prompt: prompt, requestedTerm: input.term)
        } catch let failure as EnrichmentFailure {
            guard case .validation(let errors) = failure else { throw failure }
            let corrected = ExamPromptLibrary.withCorrection(prompt, EntryValidator.correctionMessage(for: errors))
            return try await requestSingle(prompt: corrected, requestedTerm: input.term)
        }
    }

    private func requestSingle(prompt: String, requestedTerm: String) async throws -> WordEntry {
        let text: String
        do {
            text = try await generator.generateJSON(
                system: prompts.system,
                prompt: prompt,
                schema: try prompts.wordSchema(),
                maxOutputTokens: 4096
            )
        } catch {
            throw EnrichmentFailure.request(error.localizedDescription)
        }
        guard let entry = try? JSONDecoder().decode(WordEntry.self, from: Data(text.utf8)) else {
            throw EnrichmentFailure.validation([.empty("json")])
        }
        let errors = EntryValidator.validate(entry, requestedTerm: requestedTerm)
        guard errors.isEmpty else { throw EnrichmentFailure.validation(errors) }
        return entry
    }

    // MARK: 일괄 (SPEC §6.2)

    /// 최대 10개씩 요청한다. 실패한 항목만 교정 메모와 함께 다음 배치로 다시 넣는다(최대 2회).
    func enrichBatch(_ inputs: [EnrichmentInput]) async -> [UUID: Result<WordEntry, EnrichmentFailure>] {
        var results: [UUID: Result<WordEntry, EnrichmentFailure>] = [:]
        var pending = inputs
        var lastErrors: [UUID: [EntryValidationError]] = [:]

        for attempt in 0...Self.batchRetryLimit where !pending.isEmpty {
            var prompt = prompts.batchPrompt(for: pending)
            if attempt > 0 {
                let notes = pending.map { input in
                    let codes = EntryValidator.correctionMessage(for: lastErrors[input.id] ?? [.empty("item")])
                    return "id \(input.id.uuidString) (\(input.term)):\n\(codes)"
                }
                prompt = ExamPromptLibrary.withCorrection(prompt, notes.joined(separator: "\n"))
            }

            let text: String
            do {
                text = try await generator.generateJSON(
                    system: prompts.system,
                    prompt: prompt,
                    schema: try prompts.batchSchema(),
                    maxOutputTokens: 16_384
                )
            } catch {
                // 네트워크·키 오류는 다시 보내도 같으므로 남은 항목을 실패로 끝낸다.
                for input in pending {
                    results[input.id] = .failure(.request(error.localizedDescription))
                }
                return results
            }

            let entries = (try? JSONDecoder().decode([WordEntry].self, from: Data(text.utf8))) ?? []
            let entriesByID = Dictionary(
                entries.compactMap { entry in entry.id.flatMap(UUID.init(uuidString:)).map { ($0, entry) } },
                uniquingKeysWith: { first, _ in first }
            )

            var stillPending: [EnrichmentInput] = []
            for input in pending {
                guard let entry = entriesByID[input.id] else {
                    lastErrors[input.id] = [.empty("item")]
                    stillPending.append(input)
                    continue
                }
                let errors = EntryValidator.validate(entry, requestedTerm: input.term)
                if errors.isEmpty {
                    results[input.id] = .success(entry)
                } else {
                    lastErrors[input.id] = errors
                    stillPending.append(input)
                }
            }
            pending = stillPending
        }

        for input in pending {
            results[input.id] = .failure(.validation(lastErrors[input.id] ?? [.empty("item")]))
        }
        return results
    }
}
