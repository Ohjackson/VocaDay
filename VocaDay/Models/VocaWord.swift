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
}
