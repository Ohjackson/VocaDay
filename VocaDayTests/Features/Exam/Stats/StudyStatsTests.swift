import XCTest
@testable import VocaDay

final class StudyStatsTests: XCTestCase {
    private func word(_ term: String, stage: Int, next: Int, idk: Int = 0, day: UUID? = nil, created: Double = 0) -> StatsWord {
        StatsWord(
            id: UUID(), term: term, meaningKo: "뜻", card: SRSCardState(stage: stage, nextLearningDay: next, idkCount: idk),
            createdAt: Date(timeIntervalSince1970: created), dayID: day, dayTitle: day == nil ? "" : "Day",
            dayCreatedAt: day == nil ? nil : Date(timeIntervalSince1970: 0), isEnriched: stage > 3
        )
    }

    private func session(day: Int, retry: [UUID] = []) -> SRSSessionState {
        SRSSessionState(currentLearningDay: day, sessionInProgress: !retry.isEmpty, firstSessionCompletionTime: nil, wrongAnswerWordIDs: retry)
    }

    func testDistributionAndBuckets() {
        let words = [
            word("a", stage: 0, next: 0), word("b", stage: 0, next: 0), word("c", stage: 3, next: 9),
            word("d", stage: 6, next: 20), word("e", stage: 10, next: 90),
        ]
        let stats = StudyStats(words: words, session: session(day: 5))
        XCTAssertEqual(stats.stageHistogram, [2, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1])
        XCTAssertEqual(stats.bucketCounts[.new], 2)
        XCTAssertEqual(stats.bucketCounts[.learning], 1)
        XCTAssertEqual(stats.bucketCounts[.familiar], 1)
        XCTAssertEqual(stats.bucketCounts[.longTerm], 1)
        XCTAssertEqual(stats.enrichedCount, 2)
        XCTAssertEqual(stats.learningDaysUntilNext(words[2]), 4)
        XCTAssertEqual(stats.learningDaysUntilNext(words[0]), 0)
    }

    func testDueBacklogAndRetry() {
        let words = (0..<130).map { word("w\($0)", stage: 1, next: 2, created: Double($0)) }
        let stats = StudyStats(words: words, session: session(day: 3, retry: [words[0].id, words[1].id]))
        XCTAssertEqual(stats.dueTodayIDs.count, 100)
        XCTAssertEqual(stats.overdueTotal, 130)
        XCTAssertEqual(stats.backlogCount, 30)
        XCTAssertEqual(stats.retryPendingCount, 2)
    }

    func testScheduledCountsAndHardest() {
        let words = [
            word("a", stage: 2, next: 0, idk: 3), word("b", stage: 1, next: 1, idk: 3),
            word("c", stage: 4, next: 2, idk: 1), word("d", stage: 5, next: 2),
        ]
        let stats = StudyStats(words: words, session: session(day: 0))
        XCTAssertEqual(stats.scheduledCounts(nextLearningDays: 3), [1, 1, 2])
        XCTAssertEqual(stats.hardestWords().map(\.term), ["b", "a", "c"])
    }

    func testDayBreakdown() {
        let day = UUID()
        let words = [word("a", stage: 0, next: 0, day: day), word("b", stage: 6, next: 9, day: day), word("c", stage: 9, next: 9, day: day), word("d", stage: 0, next: 0)]
        let breakdown = StudyStats(words: words, session: session(day: 0)).dayBreakdowns
        XCTAssertEqual(breakdown.count, 1)
        XCTAssertEqual(breakdown[0].total, 3)
        XCTAssertEqual(breakdown[0].masteredRatio, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testStageBuckets() {
        XCTAssertEqual((0...10).map { StageBucket.of(stage: $0) }, [.new, .learning, .learning, .learning, .learning, .familiar, .familiar, .familiar, .longTerm, .longTerm, .longTerm])
    }
}
