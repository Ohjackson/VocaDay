import Foundation

/// 단고초 `SRSCard`의 값 복사본.
nonisolated struct SRSCardState: Equatable, Codable, Sendable {
    var stage: Int
    var nextLearningDay: Int
    var idkCount: Int

    static let initial = SRSCardState(stage: 0, nextLearningDay: 0, idkCount: 0)

    /// stage 0이고 틀린 적도 없으면 한 번도 채점되지 않은 단어다 (맞히면 stage가 오르고, 틀리면 idkCount가 오른다).
    var isNeverGraded: Bool { stage == 0 && idkCount == 0 }
}

/// 단고초 `UserProfile.currentLearningDay` + `UserSettings.srs_*`의 값 복사본.
nonisolated struct SRSSessionState: Equatable, Sendable {
    var currentLearningDay: Int
    var sessionInProgress: Bool
    var firstSessionCompletionTime: Date?
    var wrongAnswerWordIDs: [UUID]

    static let initial = SRSSessionState(
        currentLearningDay: 0,
        sessionInProgress: false,
        firstSessionCompletionTime: nil,
        wrongAnswerWordIDs: []
    )
}

nonisolated enum SRSSessionKind: String, Codable, Sendable {
    case first
    case retry
}

/// 단고초 `HomeViewModel.SessionStatus`.
nonisolated enum SRSSessionStatus: Equatable, Sendable {
    case readyForFirstSession
    case waitingForRetry(remainingTime: String, availableAt: Date)
    case readyForRetry

    var buttonTitle: String {
        switch self {
        case .readyForFirstSession: "오늘의 학습 시작"
        case .waitingForRetry(let remainingTime, _): "재도전까지 \(remainingTime) 남음"
        case .readyForRetry: "재도전 학습 시작"
        }
    }

    var isButtonEnabled: Bool {
        switch self {
        case .readyForFirstSession, .readyForRetry: true
        case .waitingForRetry: false
        }
    }
}

nonisolated struct SRSDueCandidate: Sendable {
    var wordID: UUID
    var card: SRSCardState
    var createdAt: Date
}

nonisolated struct SRSSessionOutcome: Equatable, Sendable {
    var cards: [UUID: SRSCardState]
    var session: SRSSessionState
    /// 1차 세션에서 틀려 재도전으로 넘어간 단어. 비어 있지 않으면 재도전 알림을 예약한다.
    var retryWordIDs: [UUID]
}

/// 단고초 `SRSManager` + `SRSCardsViewModel.process…Results`의 규칙. 수치·동작을 바꾸지 말 것 (SPEC §2).
nonisolated enum SRSEngine {
    static let baseGaps: [Int] = [0, 1, 1, 2, 2, 4, 7, 13, 30, 40, 50]
    static let dailyReviewLimit = 100
    static let retryDelayHours = 6
    static var maxStage: Int { baseGaps.count - 1 }

    // MARK: 카드 규칙

    /// 1차 학습에서 맞혔을 때.
    static func markKnown(_ card: SRSCardState, currentLearningDay: Int) -> SRSCardState {
        var card = card
        let newStage = min(card.stage + 1, maxStage)
        card.stage = newStage
        card.nextLearningDay = currentLearningDay + baseGaps[newStage]
        return card
    }

    /// 1차 학습에서 틀렸을 때. nextLearningDay는 그대로 둔다.
    static func markWrong(_ card: SRSCardState) -> SRSCardState {
        var card = card
        card.idkCount += 1
        card.stage = max(card.stage - 1, 0)
        return card
    }

    /// 재도전에서 맞혔을 때. markKnown과 같다.
    static func retryMarkKnown(_ card: SRSCardState, currentLearningDay: Int) -> SRSCardState {
        markKnown(card, currentLearningDay: currentLearningDay)
    }

    /// 재도전에서 틀렸을 때. 다음 학습일은 바로 다음 날.
    static func retryMarkWrong(_ card: SRSCardState, currentLearningDay: Int) -> SRSCardState {
        var card = card
        card.idkCount += 1
        card.stage = max(card.stage - 1, 0)
        card.nextLearningDay = currentLearningDay + 1
        return card
    }

    // MARK: 오늘의 대상

    /// nextLearningDay <= currentLearningDay, nextLearningDay 오름차순 → 생성일 오름차순, 최대 100개.
    static func dueWordIDs(
        from candidates: [SRSDueCandidate],
        currentLearningDay: Int,
        limit: Int = dailyReviewLimit
    ) -> [UUID] {
        candidates
            .filter { $0.card.nextLearningDay <= currentLearningDay }
            .sorted { lhs, rhs in
                if lhs.card.nextLearningDay != rhs.card.nextLearningDay {
                    return lhs.card.nextLearningDay < rhs.card.nextLearningDay
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.wordID.uuidString < rhs.wordID.uuidString
            }
            .prefix(limit)
            .map(\.wordID)
    }

    // MARK: 세션 결과

    /// `processFirstSessionResults`. results는 풀이 순서대로의 (단어, 정답 여부). 삭제된 단어(cards에 없음)는 건너뛴다.
    static func processFirstSession(
        results: [(wordID: UUID, isCorrect: Bool)],
        cards: [UUID: SRSCardState],
        session: SRSSessionState,
        now: Date
    ) -> SRSSessionOutcome {
        let day = session.currentLearningDay
        var updated: [UUID: SRSCardState] = [:]
        var wrongIDs: [UUID] = []

        for result in results {
            guard let card = updated[result.wordID] ?? cards[result.wordID] else { continue }
            if result.isCorrect {
                updated[result.wordID] = markKnown(card, currentLearningDay: day)
            } else {
                updated[result.wordID] = markWrong(card)
                wrongIDs.append(result.wordID)
            }
        }

        var newSession = session
        if wrongIDs.isEmpty {
            newSession.currentLearningDay += 1
            newSession.sessionInProgress = false
            newSession.wrongAnswerWordIDs = []
            newSession.firstSessionCompletionTime = nil
        } else {
            newSession.sessionInProgress = true
            newSession.firstSessionCompletionTime = now
            newSession.wrongAnswerWordIDs = wrongIDs
        }
        return SRSSessionOutcome(cards: updated, session: newSession, retryWordIDs: wrongIDs)
    }

    /// `completeRetryLearningSession`. 결과와 무관하게 학습일 +1, 세션 상태 초기화.
    static func processRetrySession(
        results: [(wordID: UUID, isCorrect: Bool)],
        cards: [UUID: SRSCardState],
        session: SRSSessionState
    ) -> SRSSessionOutcome {
        let day = session.currentLearningDay
        var updated: [UUID: SRSCardState] = [:]

        for result in results {
            guard let card = updated[result.wordID] ?? cards[result.wordID] else { continue }
            updated[result.wordID] = result.isCorrect
                ? retryMarkKnown(card, currentLearningDay: day)
                : retryMarkWrong(card, currentLearningDay: day)
        }

        var newSession = session
        newSession.currentLearningDay += 1
        newSession.sessionInProgress = false
        newSession.wrongAnswerWordIDs = []
        newSession.firstSessionCompletionTime = nil
        return SRSSessionOutcome(cards: updated, session: newSession, retryWordIDs: [])
    }

    // MARK: 홈 버튼 상태

    static func sessionStatus(
        for session: SRSSessionState,
        now: Date,
        calendar: Calendar = .current
    ) -> SRSSessionStatus {
        guard session.sessionInProgress else {
            return .readyForFirstSession
        }
        guard let completionTime = session.firstSessionCompletionTime,
              let retryAvailableTime = calendar.date(byAdding: .hour, value: retryDelayHours, to: completionTime) else {
            return .readyForRetry
        }
        guard now < retryAvailableTime else {
            return .readyForRetry
        }
        let remaining = calendar.dateComponents([.hour, .minute], from: now, to: retryAvailableTime)
        let text = String(format: "%02d:%02d", remaining.hour ?? 0, remaining.minute ?? 0)
        return .waitingForRetry(remainingTime: text, availableAt: retryAvailableTime)
    }

    static func retryAvailableDate(after completion: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: retryDelayHours, to: completion)
            ?? completion.addingTimeInterval(TimeInterval(retryDelayHours * 3600))
    }
}
