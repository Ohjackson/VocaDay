import Foundation
import SwiftData

@Model
final class VocaWord {
    var id: UUID = UUID()
    var english: String = ""
    var meaningKo: String = ""
    var exampleEn: String = ""
    var exampleKo: String = ""
    var note: String = ""
    var toeicTag: String = ""
    var createdAt: Date = Date()
    var reviewCount: Int = 0
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var masteryLevel: Int = 0
    var status: String = WordStatus.new.rawValue
    var nextReviewAt: Date = Date()
    var lastReviewedAt: Date?
    var day: VocabularyDay?

    // MARK: 시험보기 SRS (단고초 SRSCard와 같은 의미, docs/srs-port/SPEC.md §1.2)
    // 별도 엔티티 대신 단어에 둔다. CloudKit 동기화 중 기기마다 카드가 중복 생성되는 것을 막고,
    // 기본값 0이 곧 "stage 0, nextLearningDay 0" 마이그레이션이 된다.
    var srsStage: Int = 0
    var srsNextLearningDay: Int = 0
    var srsIdkCount: Int = 0

    // MARK: 시험보기 보강 데이터 (SPEC §1.1). 사용자 필드(meaningKo, exampleEn…)는 덮어쓰지 않는다.
    var quizPos: String = ""
    var quizCefr: String = ""
    var quizMeaningKo: String = ""
    var quizDisambiguationKo: String = ""
    var quizFormsJSON: String = ""
    var quizTermVariantsJSON: String = ""
    var quizExample: String = ""
    var quizExampleKo: String = ""
    var quizClozeSentence: String = ""
    var quizClozeAnswer: String = ""
    var quizClozeForm: String = ""
    var quizClozeAcceptedJSON: String = ""
    var quizNearMissJSON: String = ""
    var quizEnrichmentVersion: Int = 0
    /// 보강 당시 english·meaningKo·exampleEn 지문. 사용자가 단어를 고치면 달라져 재보강 대상이 된다.
    var quizEnrichmentFingerprint: String = ""

    init(
        id: UUID = UUID(),
        english: String,
        meaningKo: String = "",
        exampleEn: String = "",
        exampleKo: String = "",
        note: String = "",
        toeicTag: String = "",
        createdAt: Date = Date(),
        reviewCount: Int = 0,
        correctCount: Int = 0,
        wrongCount: Int = 0,
        masteryLevel: Int = 0,
        status: String = WordStatus.new.rawValue,
        nextReviewAt: Date = Date(),
        lastReviewedAt: Date? = nil,
        day: VocabularyDay? = nil
    ) {
        self.id = id
        self.english = english
        self.meaningKo = meaningKo
        self.exampleEn = exampleEn
        self.exampleKo = exampleKo
        self.note = note
        self.toeicTag = toeicTag
        self.createdAt = createdAt
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.masteryLevel = masteryLevel
        self.status = status
        self.nextReviewAt = nextReviewAt
        self.lastReviewedAt = lastReviewedAt
        self.day = day
    }
}

enum WordStatus: String, CaseIterable {
    case new = "New"
    case learning = "Learning"
    case review = "Review"
    case weak = "Weak"
    case mastered = "Mastered"

    var displayName: String {
        switch self {
        case .new: "새 단어"
        case .learning: "학습 중"
        case .review: "복습 예정"
        case .weak: "취약"
        case .mastered: "마스터"
        }
    }
}
