import Foundation
import SwiftData

enum DayFactory {
    static func nextDayTitle(existingDays: [VocabularyDay]) -> String {
        let nextNumber = existingDays
            .compactMap { Int($0.title.replacingOccurrences(of: "Day ", with: "")) }
            .max()
            .map { $0 + 1 } ?? 1

        return "Day \(nextNumber)"
    }

    static func createNextDay(existingDays: [VocabularyDay], in context: ModelContext) -> VocabularyDay {
        createDay(title: nextDayTitle(existingDays: existingDays), in: context)
    }

    static func createDay(title: String, in context: ModelContext) -> VocabularyDay {
        let day = VocabularyDay(title: title)
        context.insert(day)
        return day
    }
}
