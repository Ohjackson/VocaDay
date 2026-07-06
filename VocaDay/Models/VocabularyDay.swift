import Foundation
import SwiftData

@Model
final class VocabularyDay {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \VocaWord.day)
    var words: [VocaWord]? = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        words: [VocaWord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
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
