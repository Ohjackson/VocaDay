import SwiftData
import XCTest
@testable import VocaDay

@MainActor
final class BundledWordPackTests: XCTestCase {
    func testBundledWordsAreAllQuizReady() throws {
        let words = try BundledWordPack.loadWords(bundle: Bundle(for: VocabularyDay.self))
        XCTAssertGreaterThan(words.count, 2000)
        XCTAssertEqual(Set(words.map { $0.english.normalizedEnglish }).count, words.count, "중복 단어")
        let notReady = words.filter { !WordDataCheck.isQuizReady(WordDataCheck.issues(for: $0)) }.map(\.english)
        XCTAssertEqual(notReady, [])
    }

    private func words(_ range: ClosedRange<Int>) -> [VocaWordJSON] {
        range.map { VocaWordJSON(english: "word\($0)", meaningKo: "뜻") }
    }

    func testCandidatesSkipWordsInDaysAndSetAsideBox() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, SetAsideWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let existing = DayFactory.createDay(title: "데이 1", in: context)
        let owned = GeneratedWordDraftMapper.makeEntity(from: VocaWordJSON(english: "Word2", meaningKo: "뜻"), day: existing)
        context.insert(owned)
        existing.appendWord(owned)
        let setAside = SetAsideWord(english: " word4 ")
        context.insert(setAside)

        let candidates = BundledWordPack.candidates(from: words(1...5), existingDays: [existing], setAside: [setAside])
        XCTAssertEqual(candidates.map(\.english), ["word1", "word3", "word5"])
    }

    func testReviewRefillsSetAsideSlotsToKeepTarget() {
        var review = BundledDayReview(candidates: words(1...6), target: 3)
        XCTAssertEqual(review.current?.english, "word1")

        review.setAsideCurrent()   // word1 보관 → word4 보충
        review.keep()              // word2
        review.setAsideCurrent()   // word3 보관 → word5 보충
        XCTAssertEqual(review.queue.map(\.english), ["word1", "word2", "word3", "word4", "word5"])
        XCTAssertEqual(review.targetCount, 3)

        review.goBack()            // word3 보관 취소 → word5 빠짐
        XCTAssertEqual(review.queue.count, 4)
        XCTAssertEqual(review.current?.english, "word3")

        review.keepRemaining()
        XCTAssertTrue(review.isComplete)
        XCTAssertEqual(review.kept.map(\.english), ["word2", "word3", "word4"])
        XCTAssertEqual(review.setAside.map(\.english), ["word1"])
    }

    func testReviewKeepsFewerWhenCandidatesRunOut() {
        var review = BundledDayReview(candidates: words(1...3), target: 3)
        review.setAsideCurrent()
        review.keepRemaining()
        XCTAssertTrue(review.isComplete)
        XCTAssertEqual(review.kept.map(\.english), ["word2", "word3"])
    }

    func testAddDayStoresSetAsideWordsAndAllowsOneDayPerCalendarDay() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, SetAsideWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let day = try BundledWordPack.addDay(kept: words(1...2), setAside: words(3...3), existingDays: [], in: context, now: now)
        XCTAssertEqual(day.title, "데이 1")
        XCTAssertEqual(day.source, BundledWordPack.daySource)
        XCTAssertEqual(Set(day.wordList.map(\.english)), ["word1", "word2"])
        XCTAssertTrue(day.wordList.allSatisfy { $0.srsStage == 0 && $0.srsNextLearningDay == 0 })
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetAsideWord>()).map(\.english), ["word3"])

        XCTAssertTrue(BundledWordPack.hasAddedToday(existingDays: [day], now: now))
        XCTAssertThrowsError(try BundledWordPack.addDay(kept: words(4...4), setAside: [], existingDays: [day], in: context, now: now))

        let tomorrow = now.addingTimeInterval(86_400)
        let next = try BundledWordPack.addDay(kept: words(4...4), setAside: [], existingDays: [day], in: context, now: tomorrow)
        XCTAssertEqual(next.title, "데이 2")
    }

    func testHandMadeDayDoesNotCountAsTodaysBundledDay() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let manual = DayFactory.createDay(title: "데이 1", in: container.mainContext)
        XCTAssertFalse(BundledWordPack.hasAddedToday(existingDays: [manual]))
    }
}
