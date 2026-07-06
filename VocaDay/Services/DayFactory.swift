import Foundation
import SwiftData

enum DayFactory {
    static func createNextDay(existingDays: [VocabularyDay], in context: ModelContext) -> VocabularyDay {
        let nextNumber = existingDays
            .compactMap { Int($0.title.replacingOccurrences(of: "Day ", with: "")) }
            .max()
            .map { $0 + 1 } ?? 1

        let day = VocabularyDay(title: "Day \(nextNumber)")
        context.insert(day)
        return day
    }
}
