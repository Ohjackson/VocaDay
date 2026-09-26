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

    func testAddsNextUnusedWordsAsNewDay() throws {
        let container = try ModelContainer(for: VocabularyDay.self, VocaWord.self, configurations: .init(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let pack = (1...5).map { VocaWordJSON(english: "word\($0)", meaningKo: "뜻") }

        let existing = DayFactory.createDay(title: "데이 1", in: context)
        let owned = GeneratedWordDraftMapper.makeEntity(from: VocaWordJSON(english: "Word2", meaningKo: "뜻"), day: existing)
        context.insert(owned)
        existing.appendWord(owned)

        XCTAssertEqual(BundledWordPack.nextWords(from: pack, existingDays: [existing], count: 3).map(\.english), ["word1", "word3", "word4"])

        let day = try BundledWordPack.addNextDay(existingDays: [existing], in: context, pack: pack)
        XCTAssertEqual(day.title, "데이 2")
        XCTAssertEqual(Set(day.wordList.map(\.english)), ["word1", "word3", "word4", "word5"])
        XCTAssertTrue(day.wordList.allSatisfy { $0.srsStage == 0 && $0.srsNextLearningDay == 0 })
        XCTAssertEqual(BundledWordPack.remainingCount(in: pack, existingDays: [existing, day]), 0)
        XCTAssertThrowsError(try BundledWordPack.addNextDay(existingDays: [existing, day], in: context, pack: pack))
    }
}
