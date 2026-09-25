import XCTest
@testable import VocaDay

final class SRSForecasterTests: XCTestCase {
    func testProjectedPathMatchesGapTable() {
        let path = SRSForecaster.projectedPath(for: .initial, currentLearningDay: 0)
        XCTAssertEqual(path.map(\.learningDay), [0, 1, 2, 4, 6, 10, 17, 30, 60, 100, 150])
        XCTAssertEqual(path.map(\.stage), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10])
    }

    func testProjectedPathStartsAtNextLearningDay() {
        let path = SRSForecaster.projectedPath(for: SRSCardState(stage: 8, nextLearningDay: 40, idkCount: 1), currentLearningDay: 12)
        XCTAssertEqual(path.first, .init(learningDay: 40, stage: 9))
        XCTAssertEqual(path.dropFirst().first, .init(learningDay: 80, stage: 10))
    }

    func testSingleWordReviewsFollowOffsetsWhenAlwaysCorrect() {
        let result = SRSForecaster.run(.init(cards: [.initial], currentLearningDay: 0, days: 101))
        let reviewDays = result.days.filter { $0.served > 0.5 }.map(\.offset)
        XCTAssertEqual(reviewDays, [0, 1, 2, 4, 6, 10, 17, 30, 60, 100])
    }

    func testDailyLimitAndBacklog() {
        let cards = Array(repeating: SRSCardState.initial, count: 150)
        let result = SRSForecaster.run(.init(cards: cards, currentLearningDay: 0, days: 2))
        XCTAssertEqual(result.days[0].due, 150)
        XCTAssertEqual(result.days[0].served, 100)
        XCTAssertEqual(result.days[0].backlog, 50)
        XCTAssertEqual(result.firstOverflowOffset, 0)
        // 다음 학습일: 밀린 50 + 어제 맞힌 100(stage 1, next 1)
        XCTAssertEqual(result.days[1].due, 150)
    }

    func testMatchesEarlierSimulation() {
        let six = SRSForecaster.run(.init(cards: [], currentLearningDay: 0, days: 180, newWordsPerDay: 6))
        XCTAssertNil(six.firstOverflowOffset, "학습일당 6개, 모두 정답이면 180학습일 무초과")

        let twentyEight = SRSForecaster.run(.init(cards: [], currentLearningDay: 0, days: 30, newWordsPerDay: 28))
        XCTAssertEqual(twentyEight.firstOverflowOffset, 4, "offset 0,1,2,4 네 묶음이 겹치는 날 112개")
    }

    func testWrongAnswersIncreaseLoad() {
        let perfect = SRSForecaster.run(.init(cards: [], currentLearningDay: 0, days: 60, newWordsPerDay: 5))
        let shaky = SRSForecaster.run(.init(cards: [], currentLearningDay: 0, days: 60, accuracy: 0.7, retryAccuracy: 0.6, newWordsPerDay: 5))
        XCTAssertGreaterThan(shaky.peakDue, perfect.peakDue)
    }

    func testMassIsConservedAcrossBuckets() {
        let cards = (0..<40).map { SRSCardState(stage: $0 % 11, nextLearningDay: $0 % 5, idkCount: 0) }
        let result = SRSForecaster.run(.init(cards: cards, currentLearningDay: 0, days: 20, accuracy: 0.8, retryAccuracy: 0.5, newWordsPerDay: 2))
        for day in result.days {
            let total = day.buckets.values.reduce(0, +)
            XCTAssertEqual(total, 40 + 2 * Double(day.offset + 1), accuracy: 0.001)
        }
    }

    func testRecommendedRate() {
        XCTAssertEqual(
            SRSForecaster.recommendedNewWordsPerDay(cards: [], currentLearningDay: 0, accuracy: 1, retryAccuracy: 1, horizon: 101),
            10, "처음 100학습일은 단어당 10번 → 10개"
        )
        let shaky = SRSForecaster.recommendedNewWordsPerDay(cards: [], currentLearningDay: 0, accuracy: 0.85, retryAccuracy: 0.8)
        // 기대값 모델(난수 없음) 기준. 정답률이 낮으면 권장 속도가 내려간다.
        XCTAssertEqual(shaky, 7)
        let weak = SRSForecaster.recommendedNewWordsPerDay(cards: [], currentLearningDay: 0, accuracy: 0.7, retryAccuracy: 0.6)
        XCTAssertLessThan(weak, shaky)
    }
}
