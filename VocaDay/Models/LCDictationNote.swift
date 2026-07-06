import Foundation
import SwiftData

@Model
final class LCDictationNote {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var day: LCDictationDay?

    init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        day: LCDictationDay? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.day = day
    }
}
