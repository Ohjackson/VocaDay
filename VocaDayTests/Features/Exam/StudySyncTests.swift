import XCTest
@testable import VocaDay

/// 장부·이어하기를 기기 사이에서 합치는 규칙.
final class StudySyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let a = UUID(), b = UUID(), c = UUID()

    private func ledger(day: Int = 3, kind: SRSSessionKind = .first, _ results: [(UUID, Bool)]) -> StudyDayLedger {
        var ledger = StudyDayLedger(learningDay: day, kind: kind)
        for (id, isCorrect) in results {
            ledger.record(wordID: id, isCorrect: isCorrect, mode: .choice)
        }
        ledger.updatedAt = now
        return ledger
    }

    func testLedgersOfSameDayAreUnitedTheSameWayOnBothDevices() {
        let mine = ledger([(a, true), (b, true)])
        let theirs = ledger([(b, false), (c, true)])

        let onMine = mine.merged(with: theirs)
        let onTheirs = theirs.merged(with: mine)

        XCTAssertEqual(onMine.gradedIDs, [a, b, c])
        XCTAssertEqual(onMine.results[b.uuidString], false, "두 기기의 판단이 다르면 틀린 쪽")
        XCTAssertTrue(onMine.hasSameContent(as: onTheirs), "어느 기기에서 합쳐도 같다")
    }

    func testLaterDayLedgerWins() {
        let old = ledger(day: 3, kind: .retry, [(a, true)])
        let new = ledger(day: 4, kind: .first, [(b, true)])
        XCTAssertEqual(old.merged(with: new), new)
        XCTAssertEqual(new.merged(with: old), new)

        let first = ledger(day: 4, kind: .first, [(a, true)])
        let retry = ledger(day: 4, kind: .retry, [(b, true)])
        XCTAssertEqual(first.merged(with: retry), retry, "같은 날이면 재도전이 뒤다")
    }

    func testSameExamSessionKeepsFurthestCursorAndAllResults() {
        var mine = ActiveExamSession(kind: .first, learningDay: 3, plan: .empty)
        var theirs = mine
        mine.cursor = 2
        mine.record(wordID: a, isCorrect: true)
        theirs.cursor = 5
        theirs.record(wordID: b, isCorrect: false)
        theirs.hintedWordIDs = [b.uuidString]

        let merged = mine.merged(with: theirs)
        XCTAssertEqual(merged.cursor, 5)
        XCTAssertEqual(merged.results, [a.uuidString: true, b.uuidString: false])
        XCTAssertEqual(merged.hintedWordIDs, [b.uuidString])
        XCTAssertTrue(merged.hasSameContent(as: theirs.merged(with: mine)))
    }

    func testDifferentExamSessionsKeepTheOneFurtherAlongOnBothDevices() {
        var mine = ActiveExamSession(kind: .first, learningDay: 3, plan: .empty)
        var theirs = ActiveExamSession(kind: .first, learningDay: 3, plan: .empty)
        mine.cursor = 1
        theirs.cursor = 4
        XCTAssertEqual(mine.merged(with: theirs).sessionID, theirs.sessionID)
        XCTAssertEqual(theirs.merged(with: mine).sessionID, theirs.sessionID)
    }

    func testStoreMergesSameSessionOnSave() {
        let store = ExamSessionStore(storageKey: "test.examSync.\(UUID().uuidString)")
        defer { store.clear() }
        var ahead = ActiveExamSession(kind: .first, learningDay: 3, plan: .empty)
        var behind = ahead
        ahead.cursor = 6
        ahead.record(wordID: a, isCorrect: true)
        store.save(ahead)

        behind.cursor = 2
        behind.record(wordID: b, isCorrect: true)
        store.save(behind)

        XCTAssertEqual(store.load()?.cursor, 6, "다른 기기에서 더 푼 위치를 되돌리지 않는다")
        XCTAssertEqual(store.load()?.answeredGradedCount, 2)
    }

    // MARK: 진행 상태가 늦게 오는 기기

    private func snapshot(session: SRSSessionState, ledger: StudyDayLedger?, at date: Date? = nil) -> StudyQueueSnapshot {
        let candidates = [a, b].map { SRSDueCandidate(wordID: $0, card: SRSCardState(stage: 3, nextLearningDay: 0, idkCount: 1), createdAt: now) }
        return StudyQueue.snapshot(candidates: candidates, session: session, ledger: ledger, now: date ?? now)
    }

    func testFinalizedLedgerOfTheSameDayBlocksStudyUntilProgressSyncs() {
        var finalized = ledger(day: 3, [(a, true), (b, true)])
        finalized.finalizedAt = now
        var session = SRSSessionState.initial
        session.currentLearningDay = 3

        let waiting = snapshot(session: session, ledger: finalized)
        XCTAssertTrue(waiting.isAwaitingSync)
        XCTAssertNil(waiting.kind)
        XCTAssertFalse(waiting.isReadyToFinalize, "같은 날을 두 번 반영하지 않는다")

        session.currentLearningDay = 4
        XCTAssertFalse(snapshot(session: session, ledger: finalized).isAwaitingSync, "진행 상태가 오면 풀린다")
    }

    func testLedgerOfALaterDayBlocksStudy() {
        let later = ledger(day: 4, [(a, true)])
        var session = SRSSessionState.initial
        session.currentLearningDay = 3
        XCTAssertTrue(snapshot(session: session, ledger: later).isAwaitingSync)
    }

    func testStaleLedgerStopsBlockingAfterWaitLimit() {
        let later = ledger(day: 4, [(a, true)])
        var session = SRSSessionState.initial
        session.currentLearningDay = 3
        let date = now.addingTimeInterval(StudyDayLedger.syncWaitLimit + 1)
        let snapshot = snapshot(session: session, ledger: later, at: date)
        XCTAssertFalse(snapshot.isAwaitingSync)
        XCTAssertEqual(snapshot.kind, .first)
    }
}
