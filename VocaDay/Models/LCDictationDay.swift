import Foundation
import SwiftData

@Model
final class LCDictationDay {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \LCDictationNote.day)
    var notes: [LCDictationNote]? = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        notes: [LCDictationNote] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.notes = notes
    }

    var noteList: [LCDictationNote] {
        notes ?? []
    }

    func appendNote(_ note: LCDictationNote) {
        if notes == nil {
            notes = []
        }

        notes?.append(note)
    }
}
