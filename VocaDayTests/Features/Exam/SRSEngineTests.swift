import XCTest
@testable import VocaDay

/// SPEC §2 규칙 (단고초 SRSManager / SRSCardsViewModel 과 같은 수치·동작).
final class SRSEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(day: Int) -> SRSSessionState {
        SRSSessionState(currentLearningDay: day, sessionInProgress: false, firstSessionCompletionTime: nil, wrongAnswerWordIDs: [])
    }

    func testConstantsMatchOriginal() {
        XCTAssertEqual(SRSEngine.baseGaps, [0, 1, 1, 2, 2, 4, 7, 13, 30, 40, 50])
        XCTAssertEqual(SRSEngine.dailyReviewLimit, 100)
        XCTAssertEqual(SRSEngine.retryDelayHours, 6)
    }

    func testMarkKnownFollowsGapTable() {
        var card = SRSCardState.initial
        for stage in 1...10 {
            card = SRSEngine.markKnown(card, currentLearningDay: 20)
            XCTAssertEqual(card.stage, stage)
            XCTAssertEqual(card.nextLearningDay, 20 + SRSEngine.baseGaps[stage])
        }
    }

    func testStageTenStaysTenWhenCorrect() {
        let card = SRSEngine.markKnown(SRSCardState(stage: 10, nextLearningDay: 5, idkCount: 2), currentLearningDay: 7)
        XCTAssertEqual(card, SRSCardState(stage: 10, nextLearningDay: 57, idkCount: 2))
        XCTAssertEqual(SRSEngine.retryMarkKnown(SRSCardState(stage: 10, nextLearningDay: 5, idkCount: 0), currentLearningDay: 7).stage, 10)
    }

    func testStageZeroStaysZeroWhenWrong() {
        let first = SRSEngine.markWrong(SRSCardState(stage: 0, nextLearningDay: 3, idkCount: 0))
        XCTAssertEqual(first, SRSCardState(stage: 0, nextLearningDay: 3, idkCount: 1))
        let retry = SRSEngine.retryMarkWrong(SRSCardState(stage: 0, nextLearningDay: 3, idkCount: 1), currentLearningDay: 9)
        XCTAssertEqual(retry, SRSCardState(stage: 0, nextLearningDay: 10, idkCount: 2))
    }

    func testFirstSessionWrongKeepsNextLearningDay() {
        let card = SRSEngine.markWrong(SRSCardState(stage: 4, nextLearningDay: 12, idkCount: 0))
        XCTAssertEqual(card, SRSCardState(stage: 3, nextLearningDay: 12, idkCount: 1))
    }

    func testAllCorrectFirstSessionAdvancesDayWithoutRetry() {
        let a = UUID(), b = UUID()
        let outcome = SRSEngine.processFirstSession(
            results: [(a, true), (b, true)],
            cards: [a: .initial, b: SRSCardState(stage: 3, nextLearningDay: 4, idkCount: 0)],
            session: session(day: 4),
            now: now
        )
        XCTAssertEqual(outcome.session.currentLearningDay, 5)
        XCTAssertFalse(outcome.session.sessionInProgress)
        XCTAssertNil(outcome.session.firstSessionCompletionTime)
        XCTAssertTrue(outcome.retryWordIDs.isEmpty)
        XCTAssertEqual(outcome.cards[a], SRSCardState(stage: 1, nextLearningDay: 5, idkCount: 0))
        XCTAssertEqual(outcome.cards[b], SRSCardState(stage: 4, nextLearningDay: 6, idkCount: 0))
        XCTAssertEqual(SRSEngine.sessionStatus(for: outcome.session, now: now), .readyForFirstSession)
    }

    func testAnyWrongStartsRetryThatIsLockedForSixHours() {
        let a = UUID(), b = UUID()
        let outcome = SRSEngine.processFirstSession(
            results: [(a, true), (b, false)],
            cards: [a: .initial, b: SRSCardState(stage: 2, nextLearningDay: 4, idkCount: 0)],
            session: session(day: 4),
            now: now
        )
        XCTAssertEqual(outcome.session.currentLearningDay, 4, "틀린 게 있으면 학습일은 아직 그대로")
        XCTAssertTrue(outcome.session.sessionInProgress)
        XCTAssertEqual(outcome.session.firstSessionCompletionTime, now)
        XCTAssertEqual(outcome.session.wrongAnswerWordIDs, [b])
        XCTAssertEqual(outcome.retryWordIDs, [b])

        let justBefore = SRSEngine.sessionStatus(for: outcome.session, now: now.addingTimeInterval(6 * 3600 - 60))
        XCTAssertEqual(justBefore.buttonTitle, "재도전까지 00:01 남음")
        XCTAssertFalse(justBefore.isButtonEnabled)

        let rightAfterFirst = SRSEngine.sessionStatus(for: outcome.session, now: now)
        XCTAssertEqual(rightAfterFirst.buttonTitle, "재도전까지 06:00 남음")

        let sixHoursLater = SRSEngine.sessionStatus(for: outcome.session, now: now.addingTimeInterval(6 * 3600))
        XCTAssertEqual(sixHoursLater, .readyForRetry)
        XCTAssertTrue(sixHoursLater.isButtonEnabled)
        XCTAssertEqual(sixHoursLater.buttonTitle, "재도전 학습 시작")
    }

    func testRetrySessionSetsWrongWordsToNextDayAndAdvancesDay() {
        let right = UUID(), wrong = UUID()
        var state = session(day: 8)
        state.sessionInProgress = true
        state.firstSessionCompletionTime = now
        state.wrongAnswerWordIDs = [right, wrong]

        let outcome = SRSEngine.processRetrySession(
            results: [(right, true), (wrong, false)],
            cards: [
                right: SRSCardState(stage: 1, nextLearningDay: 8, idkCount: 1),
                wrong: SRSCardState(stage: 3, nextLearningDay: 8, idkCount: 1),
            ],
            session: state
        )
        XCTAssertEqual(outcome.cards[wrong], SRSCardState(stage: 2, nextLearningDay: 9, idkCount: 2))
        XCTAssertEqual(outcome.cards[right], SRSCardState(stage: 2, nextLearningDay: 9, idkCount: 1))
        XCTAssertEqual(outcome.session.currentLearningDay, 9)
        XCTAssertFalse(outcome.session.sessionInProgress)
        XCTAssertTrue(outcome.session.wrongAnswerWordIDs.isEmpty)
        XCTAssertNil(outcome.session.firstSessionCompletionTime)
    }

    func testRetrySessionAdvancesDayEvenIfAllWrong() {
        let wrong = UUID()
        var state = session(day: 2)
        state.sessionInProgress = true
        let outcome = SRSEngine.processRetrySession(results: [(wrong, false)], cards: [wrong: .initial], session: state)
        XCTAssertEqual(outcome.session.currentLearningDay, 3)
    }

    func testDeletedWordsAreSkipped() {
        let deleted = UUID()
        let outcome = SRSEngine.processFirstSession(results: [(deleted, false)], cards: [:], session: session(day: 1), now: now)
        XCTAssertTrue(outcome.cards.isEmpty)
        XCTAssertTrue(outcome.retryWordIDs.isEmpty)
        XCTAssertEqual(outcome.session.currentLearningDay, 2)
    }

    func testDailyLimitAndOverflowComesFirstNextSession() {
        let base = Date(timeIntervalSince1970: 0)
        let candidates = (0..<150).map { index in
            SRSDueCandidate(wordID: UUID(), card: .initial, createdAt: base.addingTimeInterval(Double(index)))
        }
        let today = SRSEngine.dueWordIDs(from: candidates, currentLearningDay: 0)
        XCTAssertEqual(today.count, 100)
        XCTAssertEqual(today, candidates.prefix(100).map(\.wordID), "nextLearningDay 같으면 생성일 오름차순")

        // 100개 모두 맞힘 → 학습일 1. 남은 50개(nextLearningDay 0)가 맨 앞에 온다.
        var cards = Dictionary(uniqueKeysWithValues: candidates.map { ($0.wordID, $0.card) })
        let outcome = SRSEngine.processFirstSession(
            results: today.map { ($0, true) },
            cards: cards,
            session: session(day: 0),
            now: now
        )
        outcome.cards.forEach { cards[$0.key] = $0.value }
        let next = SRSEngine.dueWordIDs(
            from: candidates.map { SRSDueCandidate(wordID: $0.wordID, card: cards[$0.wordID]!, createdAt: $0.createdAt) },
            currentLearningDay: outcome.session.currentLearningDay
        )
        XCTAssertEqual(Array(next.prefix(50)), candidates.suffix(50).map(\.wordID))
        XCTAssertEqual(next.count, 100, "밀린 50개 + 오늘(학습일 1) 차례인 50개")
    }

    func testDueOrderingPrefersMostOverdue() {
        let older = SRSDueCandidate(wordID: UUID(), card: SRSCardState(stage: 3, nextLearningDay: 2, idkCount: 0), createdAt: Date(timeIntervalSince1970: 100))
        let overdue = SRSDueCandidate(wordID: UUID(), card: SRSCardState(stage: 5, nextLearningDay: 1, idkCount: 0), createdAt: Date(timeIntervalSince1970: 200))
        let future = SRSDueCandidate(wordID: UUID(), card: SRSCardState(stage: 5, nextLearningDay: 9, idkCount: 0), createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(SRSEngine.dueWordIDs(from: [older, overdue, future], currentLearningDay: 3), [overdue.wordID, older.wordID])
    }
}
