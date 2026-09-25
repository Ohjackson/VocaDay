import Foundation
import SwiftData

/// 복습 카드와 시험이 함께 쓰는 SRS 진입점.
///
/// - 오늘의 대상 단어: 어느 쪽에서 풀든 첫 결과를 `StudyDayLedger`에 기록하고, 모두 채점되면
///   단고초 규칙(`SRSEngine`)으로 한 번에 반영한다 → 학습일 +1 또는 6시간 뒤 재도전.
/// - 대상이 아닌 단어(미리 복습): '다시'는 잊어버린 것이므로 단계를 낮추고 오늘 대상에 넣는다.
///   '알아요'는 간격 효과를 해치지 않도록 일정을 바꾸지 않는다 (일찍 맞힌 것은 기억 강화 효과가 작다).
@MainActor
struct SRSStudyService {
    struct Finalization {
        var kind: SRSSessionKind
        var ledger: StudyDayLedger
        var results: [(wordID: UUID, isCorrect: Bool)]
        var cardsBefore: [UUID: SRSCardState]
        var outcome: SRSSessionOutcome
        var retryScheduledAt: Date?
    }

    enum EarlyReviewResult: Equatable {
        case unchanged
        case lapsed
    }

    let context: ModelContext
    var ledgerStore: StudyDayLedgerStore = .standard
    var examStore: ExamSessionStore = .standard
    var highWater: SRSProgressHighWaterStore = .standard
    var now: () -> Date = Date.init
    var scheduleRetryReminder: (Date, Int) -> Void = { date, count in
        Task { await ExamRetryReminderService.schedule(at: date, wordCount: count) }
    }
    var cancelRetryReminder: () -> Void = ExamRetryReminderService.cancel

    private var repository: SRSRepository { SRSRepository(context: context, highWater: highWater) }

    // MARK: 현황

    func snapshot() -> StudyQueueSnapshot {
        let repository = repository
        return StudyQueue.snapshot(
            words: repository.allWords(),
            progress: repository.progress(),
            ledger: ledgerStore.load(),
            now: now()
        )
    }

    /// 오늘 세션용 장부. 학습일·세션 종류가 바뀌었으면 새로 만든다.
    func currentLedger(for snapshot: StudyQueueSnapshot) -> StudyDayLedger? {
        guard let kind = snapshot.kind else { return nil }
        if let saved = ledgerStore.load(), saved.learningDay == snapshot.learningDay, saved.kind == kind {
            return saved
        }
        return StudyDayLedger(learningDay: snapshot.learningDay, kind: kind)
    }

    // MARK: 기록

    /// 오늘 대상 단어의 결과를 장부에 쓴다. 대상이 아니거나 이미 채점된 단어는 무시한다.
    @discardableResult
    func record(_ entries: [(wordID: UUID, isCorrect: Bool, mode: ExamItemKind, detail: String?)]) -> StudyDayLedger? {
        let snapshot = snapshot()
        guard var ledger = currentLedger(for: snapshot) else { return nil }
        let targets = Set(snapshot.targetIDs)
        for entry in entries where targets.contains(entry.wordID) {
            ledger.record(wordID: entry.wordID, isCorrect: entry.isCorrect, mode: entry.mode, detail: entry.detail)
        }
        ledgerStore.save(ledger)
        return ledger
    }

    /// 복습 카드 결과. 오늘 대상이면 장부로, 아니면 미리 복습 규칙으로 처리한다.
    func recordFlashcards(_ decisions: [(wordID: UUID, known: Bool)]) -> (graded: Int, lapsed: Int) {
        let targets = Set(snapshot().targetIDs)
        let today = decisions.filter { targets.contains($0.wordID) }
        let early = decisions.filter { !targets.contains($0.wordID) }

        record(today.map { ($0.wordID, $0.known, .flashcard, nil) })
        let lapsed = early.filter { recordEarlyReview(wordID: $0.wordID, known: $0.known) == .lapsed }.count
        return (today.count, lapsed)
    }

    /// 오늘 대상이 아닌 단어를 복습했을 때.
    @discardableResult
    func recordEarlyReview(wordID: UUID, known: Bool) -> EarlyReviewResult {
        let repository = repository
        guard let word = repository.allWords().first(where: { $0.id == wordID }) else { return .unchanged }
        let progress = repository.progress()
        let before = word.srsCard
        let date = now()

        var result = EarlyReviewResult.unchanged
        if !known {
            var card = SRSEngine.markWrong(before)
            card.nextLearningDay = min(before.nextLearningDay, progress.currentLearningDay)
            word.srsCard = card
            result = .lapsed
        }
        updateLegacyCounters(word, isCorrect: known, at: date)
        context.insert(ReviewLog(
            wordID: wordID,
            sessionID: UUID(),
            learningDay: progress.currentLearningDay,
            sessionKind: SRSSessionKind.first.rawValue,
            mode: ExamItemKind.flashcard.rawValue,
            isCorrect: known,
            outcomeDetail: "early",
            stageBefore: before.stage,
            stageAfter: word.srsStage,
            answeredAt: date
        ))
        if context.saveReportingError() != nil {
            context.rollback()
            return .unchanged
        }
        if result == .lapsed {
            highWater.overwrite(word)
        }
        return result
    }

    // MARK: 반영

    /// 오늘 대상이 모두 채점됐으면 SRS에 반영한다. 아직 남았으면 nil.
    /// - Returns: 반영 결과. 저장에 실패하면 에러를 던진다.
    func finalizeIfComplete() throws -> Finalization? {
        let repository = repository
        let allWords = repository.allWords()
        repository.restoreMonotonicProgress(in: allWords)
        let progress = repository.progress()
        let snapshot = StudyQueue.snapshot(words: allWords, progress: progress, ledger: ledgerStore.load(), now: now())
        guard snapshot.isReadyToFinalize, let kind = snapshot.kind,
              let ledger = currentLedger(for: snapshot) else { return nil }

        let cardsBefore = Dictionary(allWords.map { ($0.id, $0.srsCard) }, uniquingKeysWith: { first, _ in first })
        let targets = Set(snapshot.targetIDs)
        let results = ledger.orderedResults.filter { targets.contains($0.wordID) && cardsBefore[$0.wordID] != nil }
        let completedAt = now()

        let outcome: SRSSessionOutcome = kind == .first
            ? SRSEngine.processFirstSession(results: results, cards: cardsBefore, session: progress.sessionState, now: completedAt)
            : SRSEngine.processRetrySession(results: results, cards: cardsBefore, session: progress.sessionState)

        let wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for result in results {
            if let word = wordsByID[result.wordID] {
                updateLegacyCounters(word, isCorrect: result.isCorrect, at: completedAt)
            }
        }

        guard repository.apply(outcome, to: progress, words: allWords, now: completedAt) else {
            throw FinalizationError.saveFailed
        }
        ledgerStore.clear()
        examStore.clear()
        recordLogs(ledger: ledger, results: results, cardsBefore: cardsBefore, outcome: outcome, at: completedAt)

        var retryAt: Date?
        if kind == .first, !outcome.retryWordIDs.isEmpty {
            let date = SRSEngine.retryAvailableDate(after: completedAt)
            retryAt = date
            scheduleRetryReminder(date, outcome.retryWordIDs.count)
        } else if kind == .retry {
            cancelRetryReminder()
        }

        return Finalization(
            kind: kind,
            ledger: ledger,
            results: results,
            cardsBefore: cardsBefore,
            outcome: outcome,
            retryScheduledAt: retryAt
        )
    }

    enum FinalizationError: LocalizedError {
        case saveFailed

        var errorDescription: String? { "학습 결과를 저장하지 못했어요. 다시 시도해 주세요." }
    }

    // MARK: 내부

    /// 예전 날짜 기반 복습의 누적 기록. 통계·정렬(틀린 횟수순)에서 계속 쓴다. 일정 계산에는 쓰지 않는다.
    private func updateLegacyCounters(_ word: VocaWord, isCorrect: Bool, at date: Date) {
        word.reviewCount += 1
        if isCorrect {
            word.correctCount += 1
        } else {
            word.wrongCount += 1
        }
        word.lastReviewedAt = date
    }

    private func recordLogs(
        ledger: StudyDayLedger,
        results: [(wordID: UUID, isCorrect: Bool)],
        cardsBefore: [UUID: SRSCardState],
        outcome: SRSSessionOutcome,
        at date: Date
    ) {
        for result in results {
            guard let before = cardsBefore[result.wordID], let after = outcome.cards[result.wordID] else { continue }
            let key = result.wordID.uuidString
            context.insert(ReviewLog(
                wordID: result.wordID,
                sessionID: ledger.sessionID,
                learningDay: ledger.learningDay,
                sessionKind: ledger.kind.rawValue,
                mode: ledger.modes[key] ?? "",
                isCorrect: result.isCorrect,
                outcomeDetail: ledger.details[key] ?? "",
                stageBefore: before.stage,
                stageAfter: after.stage,
                answeredAt: date
            ))
        }
        if context.saveReportingError() != nil {
            // 로그 저장 실패는 SRS 결과에 영향을 주지 않는다.
            context.rollback()
        }
    }
}
