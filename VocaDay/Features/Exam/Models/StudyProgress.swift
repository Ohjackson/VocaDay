import Foundation
import SwiftData

/// 단고초 `UserProfile.currentLearningDay` + `UserSettings.srs_*` 를 합친 시험보기 진행 상태 (SPEC §1.3).
/// 앱 전체에 하나만 있어야 하지만 CloudKit으로 기기마다 먼저 만들어질 수 있어 `StudyProgressStore`가 병합한다.
@Model
final class StudyProgress {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// 달력 날짜가 아니라 "학습을 끝낸 횟수". 세션을 완주해야 +1.
    var currentLearningDay: Int = 0
    var srsSessionInProgress: Bool = false
    var srsFirstSessionCompletionTime: Date?
    var srsWrongAnswerWordIDsJSON: String?
    var srsUpdatedAt: Date?
    /// 마지막으로 학습일을 끝낸 날짜(재도전으로 끝났으면 그 1차 세션 날짜). 하루에 학습일 하나만 진행하게 한다.
    var srsLastDayCompletedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        currentLearningDay: Int = 0,
        srsSessionInProgress: Bool = false,
        srsFirstSessionCompletionTime: Date? = nil,
        srsWrongAnswerWordIDsJSON: String? = nil,
        srsUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.currentLearningDay = currentLearningDay
        self.srsSessionInProgress = srsSessionInProgress
        self.srsFirstSessionCompletionTime = srsFirstSessionCompletionTime
        self.srsWrongAnswerWordIDsJSON = srsWrongAnswerWordIDsJSON
        self.srsUpdatedAt = srsUpdatedAt
    }

    var wrongAnswerWordIDs: [UUID] {
        get {
            guard let json = srsWrongAnswerWordIDsJSON,
                  let ids = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else {
                return []
            }
            return ids.compactMap(UUID.init(uuidString:))
        }
        set {
            if newValue.isEmpty {
                srsWrongAnswerWordIDsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue.map(\.uuidString)) {
                srsWrongAnswerWordIDsJSON = String(data: data, encoding: .utf8)
            }
        }
    }

    var sessionState: SRSSessionState {
        SRSSessionState(
            currentLearningDay: currentLearningDay,
            sessionInProgress: srsSessionInProgress,
            firstSessionCompletionTime: srsFirstSessionCompletionTime,
            wrongAnswerWordIDs: wrongAnswerWordIDs
        )
    }

    func apply(_ state: SRSSessionState, now: Date = Date()) {
        if state.currentLearningDay > currentLearningDay {
            srsLastDayCompletedAt = srsFirstSessionCompletionTime ?? now
        }
        currentLearningDay = state.currentLearningDay
        srsSessionInProgress = state.sessionInProgress
        srsFirstSessionCompletionTime = state.firstSessionCompletionTime
        wrongAnswerWordIDs = state.wrongAnswerWordIDs
        srsUpdatedAt = now
    }
}

enum StudyProgressStore {
    /// 하나만 남기고 반환한다. 여러 기기에서 만들어진 레코드는 학습일이 가장 앞선 것을 살린다.
    static func fetchOrCreate(in context: ModelContext) -> StudyProgress {
        let all = (try? context.fetch(FetchDescriptor<StudyProgress>())) ?? []
        guard let keeper = preferred(all) else {
            let progress = StudyProgress()
            context.insert(progress)
            try? context.save()
            return progress
        }

        let duplicates = all.filter { $0.id != keeper.id }
        if !duplicates.isEmpty {
            duplicates.forEach(context.delete)
            try? context.save()
        }
        return keeper
    }

    static func preferred(_ records: [StudyProgress]) -> StudyProgress? {
        records.max { lhs, rhs in
            if lhs.currentLearningDay != rhs.currentLearningDay {
                return lhs.currentLearningDay < rhs.currentLearningDay
            }
            let lhsUpdated = lhs.srsUpdatedAt ?? .distantPast
            let rhsUpdated = rhs.srsUpdatedAt ?? .distantPast
            if lhsUpdated != rhsUpdated {
                return lhsUpdated < rhsUpdated
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
