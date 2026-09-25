import SwiftData
import XCTest
@testable import VocaDay

/// SPEC §8 중 세션 흐름 항목 (SwiftData 인메모리).
@MainActor
final class ExamSessionViewModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: ExamSessionStore!
    private var ledgerStore: StudyDayLedgerStore!
    private var highWater: SRSProgressHighWaterStore!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var scheduledReminders: [(Date, Int)] = []
    private var cancelCount = 0

    override func setUp() async throws {
        container = try ModelContainer(
            for: VocabularyDay.self, VocaWord.self, StudyMemo.self, StudyPageCategory.self, StudyProgress.self, ReviewLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        store = ExamSessionStore(storageKey: "test.examSession.\(UUID().uuidString)")
        ledgerStore = StudyDayLedgerStore(storageKey: "test.ledger.\(UUID().uuidString)")
        highWater = SRSProgressHighWaterStore(defaults: UserDefaults(suiteName: "test.highWater.\(UUID().uuidString)")!)
        scheduledReminders = []
        cancelCount = 0
    }

    override func tearDown() async throws {
        store.clear()
        ledgerStore.clear()
        container = nil
        context = nil
    }

    @discardableResult
    private func seedWords(_ count: Int, stage: Int = 7, idk: Int = 1) -> [VocaWord] {
        let day = VocabularyDay(title: "Day 1")
        context.insert(day)
        let base = Date(timeIntervalSince1970: 0)
        let words = (0..<count).map { index -> VocaWord in
            let word = VocaWord(english: "word\(index)", meaningKo: "n. 뜻\(index)", createdAt: base.addingTimeInterval(Double(index)), day: day)
            word.srsStage = stage
            word.srsIdkCount = idk
            context.insert(word)
            return word
        }
        try? context.save()
        return words
    }

    private func makeViewModel() -> ExamSessionViewModel {
        ExamSessionViewModel(
            context: context,
            store: store,
            ledgerStore: ledgerStore,
            highWater: highWater,
            now: { [unowned self] in self.clock },
            scheduleRetryReminder: { [unowned self] date, count in self.scheduledReminders.append((date, count)) },
            cancelRetryReminder: { [unowned self] in self.cancelCount += 1 }
        )
    }

    /// 현재 문제를 모두 맞히거나(correct) 모두 틀린다.
    private func answerCurrent(_ viewModel: ExamSessionViewModel, correct: (UUID) -> Bool) {
        guard let item = viewModel.currentItem else { return XCTFail("문제가 없음: \(viewModel.phase)") }
        viewModel.complete(results: Dictionary(uniqueKeysWithValues: item.gradedWordIDs.map { ($0, correct($0)) }))
    }

    private func runToEnd(_ viewModel: ExamSessionViewModel, correct: (UUID) -> Bool) {
        var guardCount = 0
        while viewModel.phase == .question, !viewModel.isReplaying, guardCount < 500 {
            answerCurrent(viewModel, correct: correct)
            guardCount += 1
        }
    }

    private var progress: StudyProgress { StudyProgressStore.fetchOrCreate(in: context) }

    private func makeService() -> SRSStudyService {
        SRSStudyService(
            context: context,
            ledgerStore: ledgerStore,
            examStore: store,
            highWater: highWater,
            now: { [unowned self] in self.clock },
            scheduleRetryReminder: { [unowned self] date, count in self.scheduledReminders.append((date, count)) },
            cancelRetryReminder: { [unowned self] in self.cancelCount += 1 }
        )
    }

    // MARK: -

    func testAllCorrectAdvancesLearningDayWithoutRetry() {
        let words = seedWords(6)
        let viewModel = makeViewModel()
        viewModel.start()
        XCTAssertEqual(viewModel.gradedTotal, 6)
        runToEnd(viewModel) { _ in true }

        XCTAssertEqual(viewModel.phase, .finished)
        XCTAssertEqual(progress.currentLearningDay, 1)
        XCTAssertFalse(progress.srsSessionInProgress)
        XCTAssertTrue(scheduledReminders.isEmpty)
        XCTAssertTrue(words.allSatisfy { $0.srsStage == 8 && $0.srsNextLearningDay == 0 + SRSEngine.baseGaps[8] })
        XCTAssertNil(store.load(), "세션이 끝나면 이어하기 스냅샷을 지운다")
    }

    func testWrongAnswerLocksRetryForSixHoursAndSchedulesReminder() {
        let words = seedWords(4)
        let wrongID = words[2].id
        let viewModel = makeViewModel()
        viewModel.start()
        runToEnd(viewModel) { $0 != wrongID }

        XCTAssertEqual(viewModel.phase, .replayIntro(wrongCount: 1, hintCount: 0))
        XCTAssertEqual(progress.currentLearningDay, 0)
        XCTAssertTrue(progress.srsSessionInProgress)
        XCTAssertEqual(progress.wrongAnswerWordIDs, [wrongID])
        XCTAssertEqual(scheduledReminders.count, 1)
        XCTAssertEqual(scheduledReminders.first?.0, clock.addingTimeInterval(6 * 3600))
        XCTAssertEqual(words[2].srsStage, 6)
        XCTAssertEqual(words[2].srsIdkCount, 2)
        XCTAssertEqual(words[2].srsNextLearningDay, 0, "1차 오답은 nextLearningDay 그대로")

        // 6시간 안에는 재도전을 시작할 수 없다.
        clock = clock.addingTimeInterval(6 * 3600 - 60)
        let waiting = makeViewModel()
        waiting.start()
        XCTAssertEqual(waiting.phase, .unavailable("재도전까지 00:01 남았어요."))

        // 6시간 뒤 재도전: 또 틀리면 nextLearningDay = day + 1, 학습일 +1.
        clock = clock.addingTimeInterval(60)
        let retry = makeViewModel()
        retry.start()
        XCTAssertEqual(retry.session?.kind, .retry)
        XCTAssertEqual(retry.gradedTotal, 1)
        runToEnd(retry) { _ in false }
        XCTAssertEqual(retry.phase, .finished, "재도전에는 오답 다시 풀기를 붙이지 않는다")
        XCTAssertEqual(words[2].srsNextLearningDay, 1)
        XCTAssertEqual(words[2].srsStage, 5)
        XCTAssertEqual(progress.currentLearningDay, 1)
        XCTAssertFalse(progress.srsSessionInProgress)
        XCTAssertEqual(cancelCount, 1)
    }

    func testReplayDoesNotChangeSRSResults() throws {
        let words = seedWords(5)
        let viewModel = makeViewModel()
        viewModel.start()
        runToEnd(viewModel) { _ in false }
        XCTAssertEqual(viewModel.phase, .replayIntro(wrongCount: 5, hintCount: 0))

        let snapshot = words.map(\.srsCard)
        let progressSnapshot = progress.sessionState

        viewModel.startReplay()
        XCTAssertTrue(viewModel.isReplaying)
        // 첫 바퀴는 또 틀리고, 둘째 바퀴에 맞힌다.
        var rounds = 0
        while viewModel.isReplaying, rounds < 50 {
            let item = try XCTUnwrap(viewModel.currentItem)
            viewModel.complete(results: Dictionary(uniqueKeysWithValues: item.gradedWordIDs.map { ($0, rounds >= 5) }))
            rounds += 1
        }
        XCTAssertEqual(viewModel.phase, .finished)
        XCTAssertEqual(words.map(\.srsCard), snapshot)
        XCTAssertEqual(progress.sessionState, progressSnapshot)
        XCTAssertEqual(scheduledReminders.count, 1)
    }

    func testResumeContinuesFromSameQuestion() throws {
        seedWords(20)
        let first = makeViewModel()
        first.start()
        answerCurrent(first) { _ in true }
        let wrongCount = try XCTUnwrap(first.currentItem?.gradedWordIDs.count)
        answerCurrent(first) { _ in false }
        answerCurrent(first) { _ in true }
        let cursor = try XCTUnwrap(first.session?.cursor)
        let doneBefore = first.gradedDone
        let expectedItem = first.currentItem
        let plan = first.session?.plan

        // 앱 종료 후 재실행
        let resumed = makeViewModel()
        resumed.start()
        XCTAssertEqual(resumed.session?.cursor, cursor)
        XCTAssertEqual(resumed.session?.plan, plan)
        XCTAssertEqual(resumed.currentItem, expectedItem)
        XCTAssertEqual(resumed.gradedDone, doneBefore)
        XCTAssertTrue(resumed.wasResumed)

        runToEnd(resumed) { _ in true }
        XCTAssertEqual(progress.wrongAnswerWordIDs.count, wrongCount, "재실행 전의 오답도 결과에 들어간다")
    }

    func testStaleSnapshotFromOtherLearningDayIsDiscarded() {
        seedWords(5)
        let first = makeViewModel()
        first.start()
        answerCurrent(first) { _ in true }

        progress.currentLearningDay = 7
        try? context.save()
        let next = makeViewModel()
        next.start()
        XCTAssertEqual(next.session?.learningDay, 7)
        XCTAssertEqual(next.gradedDone, 0)
    }

    func testDeletedWordIsSkippedAndExcludedFromResults() {
        let words = seedWords(5)
        let viewModel = makeViewModel()
        viewModel.start()
        let deletedID = words[4].id
        context.delete(words[4])
        try? context.save()

        let resumed = makeViewModel()
        resumed.start()
        runToEnd(resumed) { _ in false }
        XCTAssertFalse(progress.wrongAnswerWordIDs.contains(deletedID))
        XCTAssertEqual(progress.wrongAnswerWordIDs.count, 4)
    }

    func testDailyLimitOfOneHundred() {
        seedWords(150, stage: 0, idk: 1)
        let viewModel = makeViewModel()
        viewModel.start()
        XCTAssertEqual(viewModel.gradedTotal, 100)
    }

    func testWordsWithoutExamplesSkipClozeTypes() {
        seedWords(30, stage: 0, idk: 0)
        let words = (try? context.fetch(FetchDescriptor<VocaWord>())) ?? []
        for (index, word) in words.enumerated() {
            word.srsStage = index % 11
            word.srsIdkCount = index % 11 == 0 ? 0 : 1
        }
        try? context.save()
        let viewModel = makeViewModel()
        viewModel.start()
        let kinds = Set(viewModel.session?.plan.items.map(\.kind) ?? [])
        XCTAssertTrue(kinds.isSubset(of: [.match, .meaningChoice, .koToEn]), "\(kinds)")
        runToEnd(viewModel) { _ in true }
        XCTAssertEqual(viewModel.phase, .finished)
    }

    func testSessionWritesOneReviewLogPerGradedWord() throws {
        let words = seedWords(4)
        let wrongID = words[1].id
        let viewModel = makeViewModel()
        viewModel.start()
        // 첫 문제는 오타 정답으로 기록
        let firstItem = try XCTUnwrap(viewModel.currentItem)
        let firstID = try XCTUnwrap(firstItem.gradedWordIDs.first)
        viewModel.complete(results: [firstID: firstID != wrongID], details: [firstID: "typo"])
        runToEnd(viewModel) { $0 != wrongID }

        var logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.count, 4)
        XCTAssertEqual(Set(logs.map(\.wordID)), Set(words.map(\.id)))
        let wrongLog = try XCTUnwrap(logs.first { $0.wordID == wrongID })
        XCTAssertFalse(wrongLog.isCorrect)
        XCTAssertEqual(wrongLog.stageBefore, 7)
        XCTAssertEqual(wrongLog.stageAfter, 6)
        XCTAssertEqual(wrongLog.sessionKind, "first")
        XCTAssertTrue(["M1", "M4"].contains(wrongLog.mode), "단어 4개·예문 없음 → 짝 맞추기 또는 한→영 쓰기: \(wrongLog.mode)")
        XCTAssertEqual(logs.first { $0.wordID == firstID }?.outcomeDetail, "typo")

        // 오답 다시 풀기는 로그를 남기지 않는다.
        viewModel.startReplay()
        while viewModel.isReplaying, let item = viewModel.currentItem {
            viewModel.complete(results: Dictionary(uniqueKeysWithValues: item.gradedWordIDs.map { ($0, true) }))
        }
        logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.count, 4)

        // 재도전 결과도 기록된다.
        clock = clock.addingTimeInterval(6 * 3600)
        let retry = makeViewModel()
        retry.start()
        runToEnd(retry) { _ in true }
        logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.count, 5)
        XCTAssertEqual(logs.filter { $0.sessionKind == "retry" }.map(\.wordID), [wrongID])
    }

    func testHighWaterRestoresRegressedProgress() {
        let words = seedWords(1)
        words[0].srsNextLearningDay = 9
        words[0].srsIdkCount = 3
        highWater.record(words)

        // iCloud가 예전 값을 덮어쓴 상황
        words[0].srsNextLearningDay = 2
        words[0].srsIdkCount = 1
        words[0].srsStage = 2
        XCTAssertTrue(highWater.restoreMonotonicProgress(in: words))
        XCTAssertEqual(words[0].srsNextLearningDay, 9)
        XCTAssertEqual(words[0].srsIdkCount, 3)
        XCTAssertEqual(words[0].srsStage, 2, "stage는 강등될 수 있으므로 복구하지 않는다")
    }

    // MARK: 복습 카드 + 시험 = 하나의 SRS

    func testFlashcardResultsCountTowardTodaysExam() throws {
        let words = seedWords(6)
        let service = makeService()
        _ = service.recordFlashcards([(words[0].id, true), (words[1].id, false)])

        let viewModel = makeViewModel()
        viewModel.start()
        XCTAssertEqual(Set(viewModel.session?.plan.gradedWordIDs ?? []), Set(words[2...].map(\.id)), "복습 카드로 판단한 단어는 시험에 다시 나오지 않는다")
        runToEnd(viewModel) { _ in true }

        XCTAssertEqual(viewModel.phase, .replayIntro(wrongCount: 1, hintCount: 0))
        XCTAssertEqual(progress.wrongAnswerWordIDs, [words[1].id], "복습 카드의 '다시'도 1차 오답으로 반영")
        XCTAssertEqual(words[0].srsStage, 8)
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.count, 6)
        XCTAssertEqual(logs.first { $0.wordID == words[0].id }?.mode, ExamItemKind.flashcard.rawValue)
    }

    func testFlashcardsAloneFinishTheLearningDay() throws {
        let words = seedWords(3)
        let service = makeService()
        _ = service.recordFlashcards(words.map { ($0.id, true) })
        let finalization = try XCTUnwrap(try service.finalizeIfComplete())

        XCTAssertEqual(finalization.kind, .first)
        XCTAssertEqual(progress.currentLearningDay, 1)
        XCTAssertTrue(words.allSatisfy { $0.srsStage == 8 })
        XCTAssertNil(ledgerStore.load(), "반영 후 장부를 비운다")
    }

    func testPartialFlashcardsDoNotFinalize() throws {
        let words = seedWords(3)
        let service = makeService()
        _ = service.recordFlashcards([(words[0].id, true)])
        XCTAssertNil(try service.finalizeIfComplete())
        XCTAssertEqual(service.snapshot().remainingCount, 2)
        XCTAssertEqual(progress.currentLearningDay, 0)
    }

    func testEarlyReviewAgainBringsWordIntoToday() {
        let words = seedWords(2)
        words[1].srsNextLearningDay = 13
        words[1].srsStage = 7
        try? context.save()
        highWater.record(words)
        let service = makeService()
        XCTAssertFalse(service.snapshot().targetIDs.contains(words[1].id))

        XCTAssertEqual(service.recordEarlyReview(wordID: words[1].id, known: false), .lapsed)
        XCTAssertEqual(words[1].srsStage, 6)
        XCTAssertEqual(words[1].srsNextLearningDay, 0)
        XCTAssertTrue(service.snapshot().targetIDs.contains(words[1].id), "잊은 단어는 오늘 목록에 들어간다")

        // 동기화 복구가 앞당긴 일정을 되돌리지 않는다.
        SRSRepository(context: context, highWater: highWater).restoreMonotonicProgress(in: words)
        XCTAssertEqual(words[1].srsNextLearningDay, 0)
    }

    func testEarlyReviewKnownKeepsSchedule() {
        let words = seedWords(1)
        words[0].srsNextLearningDay = 13
        try? context.save()
        XCTAssertEqual(makeService().recordEarlyReview(wordID: words[0].id, known: true), .unchanged)
        XCTAssertEqual(words[0].srsNextLearningDay, 13, "일찍 맞힌 것은 간격을 늘리지 않는다")
        XCTAssertEqual(words[0].srsStage, 7)
    }

    func testOnlyOneLearningDayPerCalendarDay() {
        seedWords(3)
        let viewModel = makeViewModel()
        viewModel.start()
        runToEnd(viewModel) { _ in true }
        XCTAssertEqual(progress.currentLearningDay, 1)

        // 같은 날: 다음 학습일 단어가 있어도 열지 않는다.
        let words = (try? context.fetch(FetchDescriptor<VocaWord>())) ?? []
        words.forEach { $0.srsNextLearningDay = 1 }
        try? context.save()
        words.forEach(highWater.overwrite)
        let snapshot = makeService().snapshot()
        XCTAssertTrue(snapshot.isDoneForToday)
        XCTAssertEqual(snapshot.upcomingCount, 3)
        let sameDay = makeViewModel()
        sameDay.start()
        XCTAssertEqual(sameDay.phase, .unavailable("오늘 학습을 마쳤어요. 다음 학습은 내일 열려요."))

        // 다음 날에는 열린다.
        clock = clock.addingTimeInterval(24 * 3600)
        XCTAssertEqual(makeService().snapshot().remainingCount, 3)
    }

    // MARK: 예문 해석

    func testViewingTranslationReplaysQuestionWithoutChangingGrade() throws {
        let words = seedWords(4)
        let viewModel = makeViewModel()
        viewModel.start()
        let item = try XCTUnwrap(viewModel.currentItem)
        viewModel.markTranslationViewed()
        runToEnd(viewModel) { _ in true }

        XCTAssertEqual(viewModel.phase, .replayIntro(wrongCount: 0, hintCount: item.gradedWordIDs.count))
        XCTAssertEqual(progress.currentLearningDay, 1, "해석을 봐도 맞힌 것은 맞은 것으로 반영")
        XCTAssertTrue(words.allSatisfy { $0.srsStage == 8 })
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(Set(logs.filter { $0.outcomeDetail == "translationHint" }.map(\.wordID)), Set(item.gradedWordIDs))

        viewModel.startReplay()
        XCTAssertTrue(viewModel.isReplaying)
        XCTAssertEqual(Set(viewModel.currentItem?.gradedWordIDs ?? []), Set(item.gradedWordIDs))
    }
}
