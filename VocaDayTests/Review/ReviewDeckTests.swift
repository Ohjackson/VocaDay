import XCTest
@testable import VocaDay

@MainActor
final class ReviewDeckTests: XCTestCase {
    private let ids = (0..<4).map { _ in UUID() }

    func testDecidingAdvancesUntilComplete() {
        var deck = ReviewDeck(wordIDs: ids)
        deck.decide(.known)
        deck.decide(.again)
        XCTAssertEqual(deck.currentWordID, ids[2])
        deck.decide(.known)
        deck.decide(.known)

        XCTAssertTrue(deck.isComplete)
        XCTAssertNil(deck.currentWordID)
        XCTAssertEqual(deck.count(of: .known), 3)
        XCTAssertEqual(deck.count(of: .again), 1)

        deck.decide(.again)
        XCTAssertEqual(deck.decisions.count, 4, "완료 후 판단은 무시되어야 합니다.")
    }

    func testGoBackUndoesLastDecision() {
        var deck = ReviewDeck(wordIDs: ids)
        deck.decide(.again)
        deck.goBack()

        XCTAssertEqual(deck.currentWordID, ids[0])
        XCTAssertTrue(deck.decisions.isEmpty)
        XCTAssertFalse(deck.canGoBack)
    }

    func testShuffleKeepsDecidedPrefix() {
        var deck = ReviewDeck(wordIDs: ids)
        deck.decide(.known)
        deck.shuffleRemaining()

        XCTAssertEqual(deck.wordIDs.first, ids[0])
        XCTAssertEqual(Set(deck.wordIDs), Set(ids))
        XCTAssertEqual(deck.currentIndex, 1)
    }

    func testSyncDropsRemovedWordsAndAppendsNewOnes() {
        var deck = ReviewDeck(wordIDs: ids)
        deck.decide(.known)
        deck.decide(.again)

        let newID = UUID()
        deck.sync(with: [ids[1], ids[2], ids[3], newID])

        XCTAssertEqual(deck.wordIDs, [ids[1], ids[2], ids[3], newID])
        XCTAssertEqual(deck.decisions, [ids[1]: .again])
        XCTAssertEqual(deck.currentWordID, ids[2])
    }
}
