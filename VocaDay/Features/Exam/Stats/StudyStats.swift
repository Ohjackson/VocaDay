import Foundation

/// stage 구간. 통계 화면 전체에서 같은 구간을 쓴다.
nonisolated enum StageBucket: Int, CaseIterable, Identifiable, Sendable {
    case new
    case learning
    case familiar
    case longTerm

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .new: "새 단어"
        case .learning: "익히는 중"
        case .familiar: "익숙함"
        case .longTerm: "장기 기억"
        }
    }

    var stages: ClosedRange<Int> {
        switch self {
        case .new: 0...0
        case .learning: 1...4
        case .familiar: 5...7
        case .longTerm: 8...10
        }
    }

    static func of(stage: Int) -> StageBucket {
        allCases.first { $0.stages.contains(stage) } ?? (stage <= 0 ? .new : .longTerm)
    }
}

/// 통계 계산용 단어 스냅샷.
nonisolated struct StatsWord: Identifiable, Equatable, Sendable {
    var id: UUID
    var term: String
    var meaningKo: String
    var card: SRSCardState
    var createdAt: Date
    var dayID: UUID?
    var dayTitle: String
    var dayCreatedAt: Date?
    var isEnriched: Bool

    var bucket: StageBucket { StageBucket.of(stage: card.stage) }
}

extension VocaWord {
    var statsWord: StatsWord {
        StatsWord(
            id: id,
            term: english.trimmingCharacters(in: .whitespacesAndNewlines),
            meaningKo: quizMeaningKo.isEmpty ? ExamText.strippingPartOfSpeechMarkers(meaningKo) : quizMeaningKo,
            card: srsCard,
            createdAt: createdAt,
            dayID: day?.id,
            dayTitle: day?.title ?? "",
            dayCreatedAt: day?.createdAt,
            isEnriched: isQuizEnrichmentCurrent
        )
    }
}

/// 현재 상태 집계 (UI와 분리).
nonisolated struct StudyStats: Sendable {
    struct DayBreakdown: Identifiable, Equatable, Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
        var counts: [StageBucket: Int]
        var total: Int

        /// 익숙함 이상 비율.
        var masteredRatio: Double {
            guard total > 0 else { return 0 }
            return Double((counts[.familiar] ?? 0) + (counts[.longTerm] ?? 0)) / Double(total)
        }
    }

    let words: [StatsWord]
    let session: SRSSessionState

    init(words: [StatsWord], session: SRSSessionState) {
        self.words = words
        self.session = session
    }

    var currentLearningDay: Int { session.currentLearningDay }

    /// stage 0…10 단어 수.
    var stageHistogram: [Int] {
        var histogram = Array(repeating: 0, count: SRSEngine.maxStage + 1)
        for word in words {
            histogram[min(max(word.card.stage, 0), SRSEngine.maxStage)] += 1
        }
        return histogram
    }

    var bucketCounts: [StageBucket: Int] {
        Dictionary(grouping: words, by: \.bucket).mapValues(\.count)
    }

    /// 오늘 세션에 나오는 단어 (최대 100개, 원본 정렬).
    var dueTodayIDs: [UUID] {
        SRSEngine.dueWordIDs(
            from: words.map { SRSDueCandidate(wordID: $0.id, card: $0.card, createdAt: $0.createdAt) },
            currentLearningDay: currentLearningDay
        )
    }

    /// 차례가 됐거나 지난 전체 단어 수.
    var overdueTotal: Int {
        words.filter { $0.card.nextLearningDay <= currentLearningDay }.count
    }

    /// 하루 상한 때문에 다음으로 밀린 단어 수.
    var backlogCount: Int {
        max(overdueTotal - SRSEngine.dailyReviewLimit, 0)
    }

    var retryPendingCount: Int {
        session.sessionInProgress ? session.wrongAnswerWordIDs.count : 0
    }

    var enrichedCount: Int {
        words.filter(\.isEnriched).count
    }

    /// 다음 복습까지 남은 학습일 (0이면 오늘).
    func learningDaysUntilNext(_ word: StatsWord) -> Int {
        max(word.card.nextLearningDay - currentLearningDay, 0)
    }

    /// 많이 틀린 순 (같으면 stage 낮은 순).
    func hardestWords(limit: Int = 10) -> [StatsWord] {
        words
            .filter { $0.card.idkCount > 0 }
            .sorted {
                $0.card.idkCount != $1.card.idkCount
                    ? $0.card.idkCount > $1.card.idkCount
                    : $0.card.stage < $1.card.stage
            }
            .prefix(limit)
            .map { $0 }
    }

    /// 앞으로 N학습일 동안 차례가 오는 단어 수 (지금 상태 그대로, 새 채점 없이).
    func scheduledCounts(nextLearningDays count: Int) -> [Int] {
        (0..<count).map { offset in
            let day = currentLearningDay + offset
            return words.filter {
                offset == 0 ? $0.card.nextLearningDay <= day : $0.card.nextLearningDay == day
            }.count
        }
    }

    /// 데이(단어장)별 구간 구성. 단어장 데이터는 읽기만 한다.
    var dayBreakdowns: [DayBreakdown] {
        Dictionary(grouping: words.filter { $0.dayID != nil }, by: { $0.dayID! })
            .map { id, dayWords in
                DayBreakdown(
                    id: id,
                    title: dayWords.first?.dayTitle ?? "",
                    createdAt: dayWords.first?.dayCreatedAt ?? .distantPast,
                    counts: Dictionary(grouping: dayWords, by: \.bucket).mapValues(\.count),
                    total: dayWords.count
                )
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
