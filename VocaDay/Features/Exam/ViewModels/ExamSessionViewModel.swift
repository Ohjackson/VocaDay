import Combine
import Foundation
import SwiftData

struct ExamResultRow: Identifiable, Equatable {
    var id: UUID
    var term: String
    var meaningKo: String
    var isCorrect: Bool
    var stageBefore: Int
    var stageAfter: Int
    /// 다음 복습까지 남은 학습일 수 (결과 반영 후 학습일 기준).
    var learningDaysUntilNext: Int
}

struct ExamResultSummary: Equatable {
    var kind: SRSSessionKind
    var rows: [ExamResultRow]
    var retryScheduledAt: Date?

    var correctCount: Int { rows.filter(\.isCorrect).count }
}

/// 세션 진행·저장·이어하기·결과 반영 (SPEC §3, §7-6). 단고초 `SRSCardsViewModel`의 결과 처리 흐름을 그대로 따른다.
@MainActor
final class ExamSessionViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case unavailable(String)
        case question
        case saveFailed(String)
        /// wrongCount: 1차 오답, hintCount: 해석을 보고 푼 문제 (둘 다 채점 없이 한 번 더).
        case replayIntro(wrongCount: Int, hintCount: Int)
        case finished
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var session: ActiveExamSession?
    @Published private(set) var currentItem: ExamPlanItem?
    @Published private(set) var isReplaying = false
    @Published private(set) var summary: ExamResultSummary?
    @Published private(set) var wasResumed = false
    /// 문제가 바뀔 때마다 올라간다. 문제 화면의 입력 상태를 초기화하는 id로 쓴다.
    @Published private(set) var itemToken = 0

    private(set) var words: [UUID: QuizWord] = [:]
    let gradingOptions: GradingOptions

    private let context: ModelContext
    private let store: ExamSessionStore
    private let ledgerStore: StudyDayLedgerStore
    private let now: () -> Date
    private let scheduleRetryReminder: (Date, Int) -> Void
    private let cancelRetryReminder: () -> Void
    private let plannerConfig: SessionPlannerConfig
    private let highWater: SRSProgressHighWaterStore

    private var hasProcessedCurrentResults = false
    /// 복습 카드·시험을 합친 오늘 채점 현황 (진행 바에 쓴다).
    @Published private(set) var ledgerGradedIDs: Set<UUID> = []
    /// 계획을 다 풀었는데 새로 대상이 된 단어가 있어 다시 계획한 횟수 (무한 반복 방지).
    private var replanCount = 0
    private var replayQueue: [ExamPlanItem] = []
    private var replayIndex = 0
    private var replayRound = 0
    private var replayWrongIDs: [UUID] = []

    init(
        context: ModelContext,
        store: ExamSessionStore = .standard,
        ledgerStore: StudyDayLedgerStore = .standard,
        gradingOptions: GradingOptions = ExamSettingsKeys.gradingOptions(),
        plannerConfig: SessionPlannerConfig = ExamSettingsKeys.plannerConfig(),
        highWater: SRSProgressHighWaterStore? = nil,
        now: @escaping () -> Date = Date.init,
        scheduleRetryReminder: @escaping (Date, Int) -> Void = { date, count in
            Task { await ExamRetryReminderService.schedule(at: date, wordCount: count) }
        },
        cancelRetryReminder: @escaping () -> Void = ExamRetryReminderService.cancel
    ) {
        self.context = context
        self.store = store
        self.ledgerStore = ledgerStore
        self.gradingOptions = gradingOptions
        self.plannerConfig = plannerConfig
        self.highWater = highWater ?? .standard
        self.now = now
        self.scheduleRetryReminder = scheduleRetryReminder
        self.cancelRetryReminder = cancelRetryReminder
    }

    private var repository: SRSRepository { SRSRepository(context: context, highWater: highWater) }

    private var service: SRSStudyService {
        SRSStudyService(
            context: context,
            ledgerStore: ledgerStore,
            examStore: store,
            highWater: highWater,
            now: now,
            scheduleRetryReminder: scheduleRetryReminder,
            cancelRetryReminder: cancelRetryReminder
        )
    }

    // MARK: 진행률 (새 단어 카드·오답 다시 풀기 제외, 복습 카드로 이미 판단한 단어는 완료로 센다)

    var gradedTotal: Int { session?.plan.gradedCount ?? 0 }
    var gradedDone: Int {
        guard let session else { return 0 }
        return Set(session.plan.gradedWordIDs).intersection(ledgerGradedIDs).count
    }
    var progress: Double {
        gradedTotal == 0 ? 0 : Double(gradedDone) / Double(gradedTotal)
    }

    func word(_ id: UUID) -> QuizWord? { words[id] }

    /// 보기(오답 후보)가 어느 단어에서 왔는지 찾는다. 빈칸 보기는 활용형일 수 있어 표기·활용형·빈칸 정답을 모두 본다.
    func word(forChoiceOption option: String, isMeaning: Bool) -> QuizWord? {
        if isMeaning {
            return words.values.first { $0.meaningKo == option }
        }
        let key = option.lowercased()
        return words.values.first { word in
            ([word.term, word.clozeAnswer] + word.termVariants + Array(word.forms.values))
                .contains { $0.lowercased() == key }
        }
    }

    // MARK: 시작 / 이어하기

    func start() {
        let repository = repository
        let allWords = repository.allWords()
        repository.restoreMonotonicProgress(in: allWords)

        let service = service
        let snapshot = service.snapshot()
        // 예문이 여러 줄인 단어는 학습일마다 다른 줄로 빈칸을 낸다 (같은 날 이어 하면 같은 줄).
        words = Dictionary(
            allWords.map { ($0.id, $0.quizWord(exampleSeed: snapshot.learningDay)) },
            uniquingKeysWith: { first, _ in first }
        )
        ledgerGradedIDs = snapshot.gradedIDs
        guard let kind = snapshot.kind else {
            if case .waitingForRetry(let remaining, _) = snapshot.status {
                phase = .unavailable("재도전까지 \(remaining) 남았어요.")
            } else {
                phase = .unavailable("오늘 학습을 마쳤어요. 다음 학습은 내일 열려요.")
            }
            return
        }

        // 같은 학습일·같은 종류의 진행 중 세션이 있으면 이어 한다.
        if let saved = store.load(), saved.learningDay == snapshot.learningDay, saved.kind == kind {
            // 장부가 생기기 전에 저장된 세션이면 그 결과를 장부로 옮긴다 (이미 있는 결과는 무시된다).
            let entries = saved.orderedResults.map { result in
                (wordID: result.wordID, isCorrect: result.isCorrect,
                 mode: saved.mode(for: result.wordID) ?? .match, detail: saved.details?[result.wordID.uuidString])
            }
            if !entries.isEmpty, let ledger = service.record(entries) {
                ledgerGradedIDs = ledger.gradedIDs
            }
            session = saved
            wasResumed = saved.cursor > 0
            hasProcessedCurrentResults = false
            showCurrentOrAdvance()
            return
        }
        store.clear()

        // 복습 카드로 오늘 대상을 모두 판단했거나, 재도전 단어가 모두 삭제됐으면 바로 반영한다.
        if snapshot.isReadyToFinalize {
            session = ActiveExamSession(kind: kind, learningDay: snapshot.learningDay, plan: .empty)
            hasProcessedCurrentResults = false
            finishGradedPart()
            return
        }

        let targets = snapshot.remainingIDs.compactMap { words[$0] }
        guard !targets.isEmpty else {
            phase = .unavailable("오늘 복습할 단어가 없어요.")
            return
        }

        let plan = SessionPlanner.plan(
            targets: targets,
            allWords: Array(words.values).sorted { $0.createdAt < $1.createdAt },
            kind: kind,
            learningDay: snapshot.learningDay,
            config: plannerConfig
        )
        let newSession = ActiveExamSession(kind: kind, learningDay: snapshot.learningDay, plan: plan)
        session = newSession
        store.save(newSession)
        hasProcessedCurrentResults = false
        showCurrentOrAdvance()
    }

    // MARK: 문제 진행

    /// 문제 하나를 마쳤을 때. results는 이 문제의 채점 대상 단어별 첫 결과, details는 "typo"/"nearMiss" 표시.
    func complete(results: [UUID: Bool], details: [UUID: String] = [:]) {
        if isReplaying {
            completeReplay(results: results)
            return
        }
        guard var current = session, let item = currentItem else { return }
        let hinted = Set(current.hintedWordIDs ?? [])
        var details = details
        for id in item.gradedWordIDs where details[id] == nil && hinted.contains(id.uuidString) {
            details[id] = "translationHint"
        }
        var entries: [(wordID: UUID, isCorrect: Bool, mode: ExamItemKind, detail: String?)] = []
        for id in item.gradedWordIDs {
            if let isCorrect = results[id] {
                current.record(wordID: id, isCorrect: isCorrect, detail: details[id])
                entries.append((id, isCorrect, item.kind, details[id]))
            }
        }
        if let ledger = service.record(entries) {
            ledgerGradedIDs = ledger.gradedIDs
        }
        // 레슨 사이 쉬는 화면 없이 바로 다음 문제로 간다 (중간에 닫아도 진행 상황은 저장된다).
        current.cursor += 1
        session = current
        store.save(current)
        showCurrentOrAdvance()
    }

    /// 문제 중에 예문 해석을 열었다. 채점은 그대로 하고, 세션 끝에 같은 문제를 한 번 더 낸다.
    func markTranslationViewed() {
        guard !isReplaying, var current = session, let item = currentItem else { return }
        var hinted = current.hintedWordIDs ?? []
        for id in item.gradedWordIDs.map(\.uuidString) where !hinted.contains(id) {
            hinted.append(id)
        }
        current.hintedWordIDs = hinted
        session = current
        store.save(current)
    }

    /// 삭제된 단어는 건너뛰고, 남은 문제가 없으면 결과를 반영한다.
    private func showCurrentOrAdvance() {
        guard var current = session else { return }
        while current.cursor < current.plan.items.count {
            if let item = presentable(current.plan.items[current.cursor]) {
                session = current
                currentItem = item
                itemToken += 1
                phase = .question
                return
            }
            current.cursor += 1
        }
        session = current
        store.save(current)
        currentItem = nil
        finishGradedPart()
    }

    private func presentable(_ item: ExamPlanItem) -> ExamPlanItem? {
        var item = item
        // 계획 뒤에 복습 카드로 판단한 단어는 다시 묻지 않는다 (오답 다시 풀기는 예외).
        item.wordIDs = item.wordIDs.filter { words[$0] != nil && (isReplaying || !ledgerGradedIDs.contains($0)) }
        item.fillerWordIDs = item.fillerWordIDs.filter { words[$0] != nil }
        guard !item.wordIDs.isEmpty else { return nil }
        if item.kind == .match, item.wordIDs.count + item.fillerWordIDs.count < 2 { return nil }
        return item
    }

    // MARK: 결과 반영 (한 번만)

    func retrySaving() {
        finishGradedPart()
    }

    private func finishGradedPart() {
        guard !hasProcessedCurrentResults, let current = session else { return }
        hasProcessedCurrentResults = true

        let finalization: SRSStudyService.Finalization?
        do {
            finalization = try service.finalizeIfComplete()
        } catch {
            hasProcessedCurrentResults = false
            phase = .saveFailed(error.localizedDescription)
            return
        }

        guard let finalization else {
            // 계획을 다 풀었지만 아직 대상이 남았다 (도중에 복습 카드에서 '다시'로 새 대상이 생긴 경우 등).
            store.clear()
            guard replanCount < 2 else {
                phase = .unavailable("남은 단어를 불러오지 못했어요. 잠시 뒤 다시 시작해 주세요.")
                return
            }
            replanCount += 1
            start()
            return
        }
        replanCount = 0
        ledgerGradedIDs = []

        let outcome = finalization.outcome
        let nextDay = outcome.session.currentLearningDay
        summary = ExamResultSummary(
            kind: finalization.kind,
            rows: finalization.results.compactMap { result in
                guard let before = finalization.cardsBefore[result.wordID], let after = outcome.cards[result.wordID] else { return nil }
                let word = words[result.wordID]
                return ExamResultRow(
                    id: result.wordID,
                    term: word?.term ?? "",
                    meaningKo: word?.meaningKo ?? "",
                    isCorrect: result.isCorrect,
                    stageBefore: before.stage,
                    stageAfter: after.stage,
                    learningDaysUntilNext: max(after.nextLearningDay - nextDay, 0)
                )
            },
            retryScheduledAt: finalization.retryScheduledAt
        )

        // 1차 세션에서 틀린 단어는 "오답 다시 풀기"로 한 번 더 (채점 X). 재도전 세션에는 붙이지 않는다.
        // 해석을 본 문제도 (맞혔더라도) 해석 없이 한 번 더 푼다. 재도전 세션에도 붙인다.
        let wrongIDs = current.kind == .first ? outcome.retryWordIDs : []
        let hintedIDs = (current.hintedWordIDs ?? []).compactMap(UUID.init(uuidString:))
            .filter { id in !wrongIDs.contains(id) && finalization.results.contains { $0.wordID == id } }
        if !wrongIDs.isEmpty || !hintedIDs.isEmpty {
            replayRound = 0
            replayWrongIDs = wrongIDs + hintedIDs
            phase = .replayIntro(wrongCount: wrongIDs.count, hintCount: hintedIDs.count)
        } else {
            phase = .finished
        }
    }

    // MARK: 오답 다시 풀기 (SRS 반영 X, 맞힐 때까지)

    func startReplay() {
        replayRound += 1
        replayQueue = SessionPlanner.replayItems(
            wrongWordIDs: replayWrongIDs,
            originalPlan: session?.plan ?? .empty,
            allWords: Array(words.values).sorted { $0.createdAt < $1.createdAt },
            round: replayRound,
            config: plannerConfig
        ).compactMap(presentable)
        replayIndex = 0
        replayWrongIDs = []
        isReplaying = true
        showNextReplay()
    }

    func skipReplay() {
        isReplaying = false
        currentItem = nil
        phase = .finished
    }

    private func completeReplay(results: [UUID: Bool]) {
        guard let item = currentItem else { return }
        replayWrongIDs += item.gradedWordIDs.filter { results[$0] == false }
        replayIndex += 1
        showNextReplay()
    }

    private func showNextReplay() {
        if replayIndex < replayQueue.count {
            currentItem = replayQueue[replayIndex]
            itemToken += 1
            phase = .question
        } else if !replayWrongIDs.isEmpty {
            startReplay()
        } else {
            isReplaying = false
            currentItem = nil
            phase = .finished
        }
    }
}
