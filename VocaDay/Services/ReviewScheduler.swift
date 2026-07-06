import Foundation

enum ReviewScheduler {
    static func markKnown(_ word: VocaWord, now: Date = Date()) {
        word.correctCount += 1
        word.reviewCount += 1
        word.masteryLevel = min(word.masteryLevel + 1, 4)
        word.lastReviewedAt = now
        word.status = status(for: word).rawValue
        word.nextReviewAt = nextReviewDate(for: word.masteryLevel, from: now)
    }

    static func markAgain(_ word: VocaWord, now: Date = Date()) {
        word.wrongCount += 1
        word.reviewCount += 1
        word.masteryLevel = max(word.masteryLevel - 1, 0)
        word.lastReviewedAt = now
        word.status = status(for: word).rawValue
        word.nextReviewAt = Calendar.current.startOfDay(for: now)
    }

    static func isDue(_ word: VocaWord, now: Date = Date()) -> Bool {
        word.nextReviewAt <= now
    }

    private static func status(for word: VocaWord) -> WordStatus {
        if word.wrongCount >= 3 && word.masteryLevel < 4 {
            return .weak
        }

        switch word.masteryLevel {
        case 0:
            return word.reviewCount == 0 ? .new : .learning
        case 1:
            return .learning
        case 2...3:
            return .review
        default:
            return .mastered
        }
    }

    private static func nextReviewDate(for masteryLevel: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        let days: Int

        switch masteryLevel {
        case 0:
            days = 0
        case 1:
            days = 1
        case 2:
            days = 3
        case 3:
            days = 7
        default:
            days = 14
        }

        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
    }
}
