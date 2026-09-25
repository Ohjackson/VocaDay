import Foundation
import SwiftData

extension VocaWord {
    var srsCard: SRSCardState {
        get { SRSCardState(stage: srsStage, nextLearningDay: srsNextLearningDay, idkCount: srsIdkCount) }
        set {
            srsStage = newValue.stage
            srsNextLearningDay = newValue.nextLearningDay
            srsIdkCount = newValue.idkCount
        }
    }
}

/// 단고초 `SRSManager`의 저장소 쪽. 규칙 자체는 `SRSEngine`에 있다.
@MainActor
struct SRSRepository {
    let context: ModelContext
    var highWater: SRSProgressHighWaterStore = .standard

    func allWords() -> [VocaWord] {
        (try? context.fetch(FetchDescriptor<VocaWord>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func progress() -> StudyProgress {
        StudyProgressStore.fetchOrCreate(in: context)
    }

    /// iCloud 동기화로 nextLearningDay·idkCount가 과거 값으로 되돌아온 경우 복구한다.
    func restoreMonotonicProgress(in words: [VocaWord]) {
        if highWater.restoreMonotonicProgress(in: words) {
            _ = context.saveReportingError()
        }
    }

    func dueWords(currentLearningDay: Int, among words: [VocaWord]) -> [VocaWord] {
        let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = SRSEngine.dueWordIDs(
            from: words.map { SRSDueCandidate(wordID: $0.id, card: $0.srsCard, createdAt: $0.createdAt) },
            currentLearningDay: currentLearningDay
        )
        return ids.compactMap { byID[$0] }
    }

    func retryWords(ids: [UUID], among words: [VocaWord]) -> [VocaWord] {
        let wanted = Set(ids)
        return words.filter { wanted.contains($0.id) }
    }

    /// 결과를 단어와 진행 상태에 반영하고 저장한다. 실패하면 rollback 후 false.
    @discardableResult
    func apply(_ outcome: SRSSessionOutcome, to progress: StudyProgress, words: [VocaWord], now: Date = Date()) -> Bool {
        for word in words {
            if let card = outcome.cards[word.id] {
                word.srsCard = card
            }
        }
        progress.apply(outcome.session, now: now)

        do {
            try context.save()
        } catch {
            context.rollback()
            #if DEBUG
            print("SRSRepository failed to save: \(error)")
            #endif
            return false
        }
        highWater.record(allWords())
        return true
    }
}

/// 단고초 `SRSProgressHighWaterStore`. iCloud 동기화로 예전 값이 덮어써져도 nextLearningDay·idkCount가 역행하지 않게 한다.
/// stage는 오답 시 의도적으로 내려가므로 복구하지 않는다.
struct SRSProgressHighWaterStore {
    private struct Value: Codable {
        var stage: Int
        var nextLearningDay: Int
        var idkCount: Int

        func merged(with card: SRSCardState) -> Value {
            Value(
                stage: max(stage, card.stage),
                nextLearningDay: max(nextLearningDay, card.nextLearningDay),
                idkCount: max(idkCount, card.idkCount)
            )
        }
    }

    static let standard = SRSProgressHighWaterStore(defaults: .standard)

    private let storageKey = "srsProgressHighWaterV1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func record(_ words: [VocaWord]) {
        var stored = load()
        for word in words {
            let key = word.id.uuidString
            stored[key] = (stored[key] ?? Value(stage: 0, nextLearningDay: 0, idkCount: 0)).merged(with: word.srsCard)
        }
        save(stored)
    }

    @discardableResult
    func restoreMonotonicProgress(in words: [VocaWord]) -> Bool {
        var stored = load()
        var changed = false

        for word in words {
            let key = word.id.uuidString
            let merged = (stored[key] ?? Value(stage: 0, nextLearningDay: 0, idkCount: 0)).merged(with: word.srsCard)
            if word.srsNextLearningDay != merged.nextLearningDay {
                word.srsNextLearningDay = merged.nextLearningDay
                changed = true
            }
            if word.srsIdkCount != merged.idkCount {
                word.srsIdkCount = merged.idkCount
                changed = true
            }
            stored[key] = merged
        }

        save(stored)
        return changed
    }

    /// 의도적으로 일정을 앞당긴 단어(복습 카드에서 '다시')는 기록을 현재 값으로 덮어써 복구 대상이 되지 않게 한다.
    func overwrite(_ word: VocaWord) {
        var stored = load()
        let card = word.srsCard
        stored[word.id.uuidString] = Value(stage: card.stage, nextLearningDay: card.nextLearningDay, idkCount: card.idkCount)
        save(stored)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }

    private func load() -> [String: Value] {
        guard let data = defaults.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: Value].self, from: data) else {
            return [:]
        }
        return values
    }

    private func save(_ values: [String: Value]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
