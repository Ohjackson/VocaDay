import Foundation
import SwiftData

@Model
final class VocabularyDay {
    var id: UUID
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \VocaWord.day)
    var words: [VocaWord]

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
}
