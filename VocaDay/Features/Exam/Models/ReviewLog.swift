import Foundation
import SwiftData

/// 풀이 로그 (SPEC §1.4). SRS 판정에는 쓰지 않고 통계에만 쓴다.
/// 채점 문제 1개당 1행, 세션 결과가 저장될 때 한꺼번에 기록한다 (오답 다시 풀기는 기록하지 않음).
@Model
final class ReviewLog {
    var id: UUID = UUID()
    var wordID: UUID = UUID()
    var sessionID: UUID = UUID()
    var learningDay: Int = 0
    /// "first" / "retry"
    var sessionKind: String = SRSSessionKind.first.rawValue
    /// "M1"…"M4"
    var mode: String = ""
    var isCorrect: Bool = false
    /// "" / "typo" / "nearMiss" (near miss 뒤 두 번째 입력으로 채점된 경우)
    var outcomeDetail: String = ""
    var stageBefore: Int = 0
    var stageAfter: Int = 0
    var answeredAt: Date = Date()

    init(
        id: UUID = UUID(),
        wordID: UUID,
        sessionID: UUID,
        learningDay: Int,
        sessionKind: String,
        mode: String,
        isCorrect: Bool,
        outcomeDetail: String = "",
        stageBefore: Int,
        stageAfter: Int,
        answeredAt: Date
    ) {
        self.id = id
        self.wordID = wordID
        self.sessionID = sessionID
        self.learningDay = learningDay
        self.sessionKind = sessionKind
        self.mode = mode
        self.isCorrect = isCorrect
        self.outcomeDetail = outcomeDetail
        self.stageBefore = stageBefore
        self.stageAfter = stageAfter
        self.answeredAt = answeredAt
    }

    var entry: ReviewLogEntry {
        ReviewLogEntry(
            wordID: wordID,
            sessionID: sessionID,
            learningDay: learningDay,
            sessionKind: SRSSessionKind(rawValue: sessionKind) ?? .first,
            mode: ExamItemKind(rawValue: mode),
            isCorrect: isCorrect,
            outcomeDetail: outcomeDetail,
            stageBefore: stageBefore,
            stageAfter: stageAfter,
            answeredAt: answeredAt
        )
    }
}

/// 통계 계산용 값 복사본.
nonisolated struct ReviewLogEntry: Equatable, Sendable {
    var wordID: UUID
    var sessionID: UUID
    var learningDay: Int
    var sessionKind: SRSSessionKind
    var mode: ExamItemKind?
    var isCorrect: Bool
    var outcomeDetail: String = ""
    var stageBefore: Int
    var stageAfter: Int
    var answeredAt: Date
}
