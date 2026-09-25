import Combine
import Foundation
import SwiftData

/// 보강 안 된(또는 사용자가 고친) 단어를 10개씩 Gemini로 보강한다 (SPEC §6.2).
/// 보강이 끝나기 전에도 시험은 M1·M4로 진행된다.
@MainActor
final class ExamEnrichmentCoordinator: ObservableObject {
    static let shared = ExamEnrichmentCoordinator()

    @Published private(set) var isRunning = false
    @Published private(set) var processedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var lastMessage: String?

    private let failureStorageKey = "examEnrichmentFailuresV1"
    private let keyStore: GeminiAPIKeyStore
    private let defaults: UserDefaults

    init(keyStore: GeminiAPIKeyStore = .standard, defaults: UserDefaults = .standard) {
        self.keyStore = keyStore
        self.defaults = defaults
    }

    var hasAPIKey: Bool { keyStore.hasAPIKey }

    /// 보강이 필요한 단어 수 (이번 지문으로 이미 실패한 단어는 제외).
    func pendingWords(in words: [VocaWord]) -> [VocaWord] {
        let failures = loadFailures()
        return words.filter { word in
            word.needsQuizEnrichment && failures[word.id.uuidString] != word.quizSourceFingerprint
        }
    }

    func failedWordCount(in words: [VocaWord]) -> Int {
        let failures = loadFailures()
        return words.filter { $0.needsQuizEnrichment && failures[$0.id.uuidString] == $0.quizSourceFingerprint }.count
    }

    func resetFailures() {
        defaults.removeObject(forKey: failureStorageKey)
    }

    func runIfPossible(context: ModelContext) {
        guard !isRunning, keyStore.hasAPIKey else { return }
        Task { await run(context: context) }
    }

    func run(context: ModelContext) async {
        guard !isRunning else { return }
        guard let apiKey = keyStore.apiKey else {
            lastMessage = GeminiError.missingAPIKey.errorDescription
            return
        }
        let prompts: ExamPromptLibrary
        do {
            prompts = try ExamPromptLibrary.load()
        } catch {
            lastMessage = error.localizedDescription
            return
        }

        let words = (try? context.fetch(FetchDescriptor<VocaWord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let pending = pendingWords(in: words)
        guard !pending.isEmpty else {
            lastMessage = nil
            return
        }

        isRunning = true
        processedCount = 0
        totalCount = pending.count
        lastMessage = nil
        defer { isRunning = false }

        let service = EnrichmentService(prompts: prompts, generator: GeminiClient(apiKey: apiKey))
        let inputs = pending.map(\.enrichmentInput)
        var failures = loadFailures()
        var succeeded = 0
        var failedCount = 0

        for start in stride(from: 0, to: inputs.count, by: EnrichmentService.batchSize) {
            let chunk = Array(inputs[start..<min(start + EnrichmentService.batchSize, inputs.count)])
            let results = await service.enrichBatch(chunk)
            let wordsByID = Dictionary(
                ((try? context.fetch(FetchDescriptor<VocaWord>())) ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var requestError: String?
            for input in chunk {
                guard let word = wordsByID[input.id] else { continue }
                switch results[input.id] {
                case .success(let entry):
                    word.applyEnrichment(entry, fingerprint: input.fingerprint)
                    failures[input.id.uuidString] = nil
                    succeeded += 1
                case .failure(.request(let message)):
                    requestError = message
                case .failure(.validation):
                    failures[input.id.uuidString] = input.fingerprint
                    failedCount += 1
                case nil:
                    break
                }
            }
            _ = context.saveReportingError()
            saveFailures(failures)
            processedCount = min(start + chunk.count, inputs.count)

            if let requestError {
                lastMessage = requestError
                return
            }
        }

        lastMessage = failedCount == 0
            ? "\(succeeded)개 단어의 시험 문제를 준비했어요."
            : "\(succeeded)개 준비, \(failedCount)개는 AI 응답이 검증을 통과하지 못했어요."
    }

    private func loadFailures() -> [String: String] {
        defaults.dictionary(forKey: failureStorageKey) as? [String: String] ?? [:]
    }

    private func saveFailures(_ failures: [String: String]) {
        defaults.set(failures, forKey: failureStorageKey)
    }
}
