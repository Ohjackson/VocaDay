import Foundation
import SwiftData

@Model
final class VocabularyDay {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var reviewSessionCount: Int = 0
    var reviewedWordCount: Int = 0
    var lastReviewedAt: Date?
    /// 데이를 만든 경로. 기본 단어장으로 만든 데이는 `BundledWordPack.daySource`. 하루 1데이 제한에 쓴다.
    var source: String = ""

    @Relationship(deleteRule: .cascade, inverse: \VocaWord.day)
    var words: [VocaWord]? = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        reviewSessionCount: Int = 0,
        reviewedWordCount: Int = 0,
        lastReviewedAt: Date? = nil,
        words: [VocaWord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.reviewSessionCount = reviewSessionCount
        self.reviewedWordCount = reviewedWordCount
        self.lastReviewedAt = lastReviewedAt
        self.words = words
    }

    var wordList: [VocaWord] {
        words ?? []
    }

    func appendWord(_ word: VocaWord) {
        if words == nil {
            words = []
        }

        words?.append(word)
    }

    func removeWord(_ word: VocaWord) {
        guard var currentWords = words else { return }
        currentWords.removeAll { $0.id == word.id }
        words = currentWords
    }
}
