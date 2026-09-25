import Foundation
import SwiftData

/// 오늘(현재 학습일) 채점 기록. 복습 카드와 시험이 **같은 장부**에 결과를 쓴다.
///
/// 오늘의 대상 단어가 모두 채점되면(어느 쪽에서든) `SRSStudyService`가 SRS 규칙으로 한 번에 반영한다.
/// 단어마다 첫 결과만 인정한다 — 먼저 푼 쪽의 판단이 그날의 채점이다.
nonisolated struct StudyDayLedger: Codable, Equatable, Sendable {
    var sessionID: UUID
    var learningDay: Int
    var kind: SRSSessionKind
    /// 단어 UUID → 정답 여부 (첫 결과만).
    var results: [String: Bool] = [:]
    /// 채점된 순서.
    var order: [String] = []
    /// 단어 UUID → 채점한 유형 (`ExamItemKind.rawValue`, 복습 카드는 "CARD").
    var modes: [String: String] = [:]
    /// 단어 UUID → "typo" / "nearMiss".
    var details: [String: String] = [:]

    init(sessionID: UUID = UUID(), learningDay: Int, kind: SRSSessionKind) {
        self.sessionID = sessionID
        self.learningDay = learningDay
        self.kind = kind
    }

    func isGraded(_ wordID: UUID) -> Bool {
        results[wordID.uuidString] != nil
    }

    var gradedIDs: Set<UUID> {
        Set(results.keys.compactMap(UUID.init(uuidString:)))
    }

    mutating func record(wordID: UUID, isCorrect: Bool, mode: ExamItemKind, detail: String? = nil) {
        let key = wordID.uuidString
        guard results[key] == nil else { return }
        results[key] = isCorrect
        order.append(key)
        modes[key] = mode.rawValue
        if let detail, !detail.isEmpty {
            details[key] = detail
        }
    }

    var orderedResults: [(wordID: UUID, isCorrect: Bool)] {
        order.compactMap { key in
            guard let id = UUID(uuidString: key), let value = results[key] else { return nil }
            return (id, value)
        }
    }
}

/// 장부 저장소. 기기 로컬(UserDefaults)에 둔다. 화면은 같은 키를 `@AppStorage`로 지켜보며 갱신된다.
nonisolated struct StudyDayLedgerStore: Sendable {
    static let storageKey = "studyDayLedgerV1"
    static let standard = StudyDayLedgerStore(storageKey: storageKey)

    let storageKey: String
    var defaults: UserDefaults { .standard }

    func load() -> StudyDayLedger? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(StudyDayLedger.self, from: data)
    }

    func save(_ ledger: StudyDayLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}

/// 오늘 풀어야 할 단어의 현황. SwiftData에 의존하지 않는 순수 계산이다.
nonisolated struct StudyQueueSnapshot: Equatable, Sendable {
    var status: SRSSessionStatus
    /// 오늘 세션 종류. 재도전 대기 중이면 nil (오늘 풀 단어 없음).
    var kind: SRSSessionKind?
    var learningDay: Int
    /// 오늘의 대상 (1차: 복습 예정 단어 최대 100개, 재도전: 1차에서 틀린 단어).
    var targetIDs: [UUID]
    /// 대상 중 복습 카드나 시험으로 이미 채점된 단어.
    var gradedIDs: Set<UUID>
    /// 오늘 학습일을 이미 끝냈으면 다음 학습을 열 수 있는 시각 (다음 날 0시).
    var nextSessionAvailableAt: Date? = nil
    /// 오늘을 끝낸 경우, 다음 학습에서 복습할 단어 수 (알림용).
    var upcomingCount: Int = 0

    var isDoneForToday: Bool { nextSessionAvailableAt != nil }

    var remainingIDs: [UUID] { targetIDs.filter { !gradedIDs.contains($0) } }
    var remainingCount: Int { remainingIDs.count }

    /// 대상이 모두 채점돼 SRS에 반영할 수 있는지. (재도전 단어가 모두 삭제된 빈 재도전도 마칠 수 있다.)
    var isReadyToFinalize: Bool {
        guard let kind else { return false }
        return remainingIDs.isEmpty && (kind == .retry || !targetIDs.isEmpty)
    }
}

nonisolated enum StudyQueue {
    /// - Parameter lastDayCompletedAt: 같은 날 이미 학습일을 끝냈으면 다음 학습은 내일 연다.
    ///   학습일은 "완료한 세션 수"라서, 막지 않으면 하루에 여러 학습일을 몰아 풀어 간격 효과가 사라진다.
    static func snapshot(
        candidates: [SRSDueCandidate],
        session: SRSSessionState,
        ledger: StudyDayLedger?,
        now: Date,
        lastDayCompletedAt: Date? = nil,
        calendar: Calendar = .current
    ) -> StudyQueueSnapshot {
        let status = SRSEngine.sessionStatus(for: session, now: now)
        if status == .readyForFirstSession, let lastDayCompletedAt, calendar.isDate(lastDayCompletedAt, inSameDayAs: now) {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return StudyQueueSnapshot(
                status: status,
                kind: nil,
                learningDay: session.currentLearningDay,
                targetIDs: [],
                gradedIDs: [],
                nextSessionAvailableAt: tomorrow,
                upcomingCount: SRSEngine.dueWordIDs(from: candidates, currentLearningDay: session.currentLearningDay).count
            )
        }
        let kind: SRSSessionKind?
        let targets: [UUID]
        switch status {
        case .readyForFirstSession:
            kind = .first
            targets = SRSEngine.dueWordIDs(from: candidates, currentLearningDay: session.currentLearningDay)
        case .readyForRetry:
            kind = .retry
            let existing = Set(candidates.map(\.wordID))
            targets = session.wrongAnswerWordIDs.filter(existing.contains)
        case .waitingForRetry:
            kind = nil
            targets = []
        }

        let validLedger = ledger.flatMap { ledger -> StudyDayLedger? in
            ledger.learningDay == session.currentLearningDay && ledger.kind == kind ? ledger : nil
        }
        let graded = (validLedger?.gradedIDs ?? []).intersection(targets)
        return StudyQueueSnapshot(
            status: status,
            kind: kind,
            learningDay: session.currentLearningDay,
            targetIDs: targets,
            gradedIDs: graded
        )
    }

    @MainActor
    static func snapshot(
        words: [VocaWord],
        progress: StudyProgress?,
        ledger: StudyDayLedger? = StudyDayLedgerStore.standard.load(),
        now: Date = Date()
    ) -> StudyQueueSnapshot {
        snapshot(
            candidates: words.map { SRSDueCandidate(wordID: $0.id, card: $0.srsCard, createdAt: $0.createdAt) },
            session: progress?.sessionState ?? .initial,
            ledger: ledger,
            now: now,
            lastDayCompletedAt: progress?.srsLastDayCompletedAt
        )
    }
}

extension StudyQueueSnapshot {
    /// 알림에 표시할 단어 수: 오늘 남은 단어, 오늘을 끝냈으면 다음 학습 단어.
    var reminderCount: Int { isDoneForToday ? upcomingCount : remainingCount }
}

extension StudyQueue {
    @MainActor
    static func snapshot(in context: ModelContext, now: Date = Date()) -> StudyQueueSnapshot {
        let words = (try? context.fetch(FetchDescriptor<VocaWord>())) ?? []
        let progress = StudyProgressStore.preferred((try? context.fetch(FetchDescriptor<StudyProgress>())) ?? [])
        return snapshot(words: words, progress: progress, now: now)
    }
}
