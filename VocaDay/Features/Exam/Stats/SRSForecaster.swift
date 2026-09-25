import Foundation

/// 앞으로의 학습 부하 예측. 난수 없이 기대값으로 계산한다 (같은 입력 → 같은 결과).
/// 카드 규칙은 `SRSEngine`의 함수를 그대로 써서 실제 동작과 어긋나지 않게 한다.
nonisolated enum SRSForecaster {
    struct Input: Equatable, Sendable {
        var cards: [SRSCardState]
        var currentLearningDay: Int
        var days: Int
        /// 1차 세션 정답률 p
        var accuracy: Double = 1
        /// 재도전 정답률 q
        var retryAccuracy: Double = 1
        /// 학습일마다 새로 추가하는 단어 수
        var newWordsPerDay: Double = 0
        var limit: Int = SRSEngine.dailyReviewLimit
    }

    struct Day: Identifiable, Equatable, Sendable {
        var offset: Int
        var learningDay: Int
        /// 그날 차례가 된 단어 (밀린 것 포함)
        var due: Double
        /// 실제로 출제되는 수 (≤ limit)
        var served: Double
        /// 상한 때문에 다음으로 밀린 수
        var backlog: Double
        var newWords: Double
        /// 그날 학습을 마친 뒤의 구간별 단어 수
        var buckets: [StageBucket: Double]
        var id: Int { offset }
        var isOverflow: Bool { backlog > 0.5 }
    }

    struct Result: Equatable, Sendable {
        var days: [Day]
        var firstOverflowOffset: Int? { days.first(where: \.isOverflow)?.offset }
        var peakDue: Double { days.map(\.due).max() ?? 0 }
    }

    private struct Key: Hashable {
        var stage: Int
        var next: Int
    }

    static func run(_ input: Input) -> Result {
        var mass: [Key: Double] = [:]
        for card in input.cards {
            mass[Key(stage: card.stage, next: card.nextLearningDay), default: 0] += 1
        }

        let p = min(max(input.accuracy, 0), 1)
        let q = min(max(input.retryAccuracy, 0), 1)
        var days: [Day] = []

        for offset in 0..<max(input.days, 0) {
            let day = input.currentLearningDay + offset
            if input.newWordsPerDay > 0 {
                mass[Key(stage: 0, next: 0), default: 0] += input.newWordsPerDay
            }

            // 원본 정렬: nextLearningDay 오름차순 (같은 next 안의 순서는 개수에 영향 없음)
            let dueKeys = mass.keys.filter { $0.next <= day }.sorted { ($0.next, $0.stage) < ($1.next, $1.stage) }
            let due = dueKeys.reduce(0) { $0 + (mass[$1] ?? 0) }
            var capacity = Double(input.limit)
            var added: [Key: Double] = [:]

            for key in dueKeys where capacity > 0 {
                guard let available = mass[key], available > 0 else { continue }
                let taken = min(available, capacity)
                capacity -= taken
                mass[key] = available - taken

                let card = SRSCardState(stage: key.stage, nextLearningDay: key.next, idkCount: 0)
                let known = SRSEngine.markKnown(card, currentLearningDay: day)
                let wrong = SRSEngine.markWrong(card)
                let retryKnown = SRSEngine.retryMarkKnown(wrong, currentLearningDay: day)
                let retryWrong = SRSEngine.retryMarkWrong(wrong, currentLearningDay: day)

                added[Key(stage: known.stage, next: known.nextLearningDay), default: 0] += taken * p
                added[Key(stage: retryKnown.stage, next: retryKnown.nextLearningDay), default: 0] += taken * (1 - p) * q
                added[Key(stage: retryWrong.stage, next: retryWrong.nextLearningDay), default: 0] += taken * (1 - p) * (1 - q)
            }

            for (key, value) in added where value > 1e-9 {
                mass[key, default: 0] += value
            }
            mass = mass.filter { $0.value > 1e-6 }

            var buckets: [StageBucket: Double] = [:]
            for (key, value) in mass {
                buckets[StageBucket.of(stage: key.stage), default: 0] += value
            }

            let served = Double(input.limit) - capacity
            days.append(Day(
                offset: offset,
                learningDay: day,
                due: due,
                served: served,
                backlog: max(due - served, 0),
                newWords: input.newWordsPerDay,
                buckets: buckets
            ))
        }
        return Result(days: days)
    }

    /// horizon 학습일 동안 한 번도 상한을 넘지 않는 최대 새 단어 속도 (0…maxRate).
    static func recommendedNewWordsPerDay(
        cards: [SRSCardState],
        currentLearningDay: Int,
        accuracy: Double,
        retryAccuracy: Double,
        horizon: Int = 180,
        maxRate: Int = 30
    ) -> Int {
        func fits(_ rate: Int) -> Bool {
            run(Input(
                cards: cards,
                currentLearningDay: currentLearningDay,
                days: horizon,
                accuracy: accuracy,
                retryAccuracy: retryAccuracy,
                newWordsPerDay: Double(rate)
            ))
            // 지금 쌓여 있는 단어가 빠지는 처음 며칠은 새 단어 속도와 무관하므로 제외
            .days.dropFirst(7).allSatisfy { !$0.isOverflow }
        }
        var low = 0
        var high = maxRate
        guard fits(0) else { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(mid) { low = mid } else { high = mid - 1 }
        }
        return low
    }

    struct PathPoint: Equatable, Sendable {
        var learningDay: Int
        /// 이 학습일에 복습을 마친 뒤의 stage
        var stage: Int
    }

    /// 계속 맞힌다고 가정한 단어 한 개의 앞으로 경로 (stage 10에 도달하고 한 번 더까지).
    static func projectedPath(for card: SRSCardState, currentLearningDay: Int) -> [PathPoint] {
        var card = card
        var day = max(card.nextLearningDay, currentLearningDay)
        var path: [PathPoint] = []
        var reachedTop = false
        while path.count < 20 {
            card = SRSEngine.markKnown(card, currentLearningDay: day)
            path.append(PathPoint(learningDay: day, stage: card.stage))
            if card.stage == SRSEngine.maxStage {
                if reachedTop { break }
                reachedTop = true
            }
            day = card.nextLearningDay
        }
        return path
    }
}
