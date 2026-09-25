import XCTest
@testable import VocaDay

final class LocalClozeTests: XCTestCase {
    func testFindsRegularInflections() throws {
        let past = try XCTUnwrap(LocalCloze.build(term: "postpone", example: "They postponed the meeting."))
        XCTAssertEqual(past.sentence, "They <> the meeting.")
        XCTAssertEqual(past.answer, "postponed")
        XCTAssertEqual(past.formClass, .ed)

        XCTAssertEqual(LocalCloze.build(term: "stop", example: "He stopped suddenly.")?.answer, "stopped")
        XCTAssertEqual(LocalCloze.build(term: "study", example: "She studies hard.")?.formClass, .s)
        XCTAssertEqual(LocalCloze.build(term: "make", example: "We are making progress.")?.answer, "making")
        XCTAssertEqual(LocalCloze.build(term: "finalize", example: "Let's finalize the plan.")?.formClass, .base)
    }

    func testFindsIrregularAndPhrasalForms() {
        XCTAssertEqual(LocalCloze.build(term: "take", example: "It took two hours.")?.answer, "took")
        XCTAssertEqual(LocalCloze.build(term: "give up", example: "She gave up smoking.")?.sentence, "She <> smoking.")
    }

    func testRespectsWordBoundariesAndCase() {
        XCTAssertNil(LocalCloze.build(term: "set", example: "Check the settings."))
        XCTAssertNil(LocalCloze.build(term: "work", example: "The worker left."), "비교급 활용은 형용사일 때만")
        XCTAssertEqual(LocalCloze.build(term: "cheap", example: "This one is cheaper.", allowsComparative: true)?.formClass, .er)
        let capitalized = LocalCloze.build(term: "register", example: "Register before Friday.")
        XCTAssertEqual(capitalized?.answer, "Register")
        XCTAssertEqual(capitalized?.sentence, "<> before Friday.")
    }

    func testUsesFirstNumberedLineThatContainsWord() {
        let example = "1. The plan was approved.\n2. They will finalize it soon."
        let cloze = LocalCloze.build(term: "finalize", example: example)
        XCTAssertEqual(cloze?.example, "They will finalize it soon.")

        let word = QuizWord.local(term: "finalize", meaningKo: "v. 완성하다", exampleEn: example, exampleKo: "1. 계획이 승인됐다.\n2. 곧 확정할 것이다.")
        XCTAssertTrue(word.hasCloze)
        XCTAssertEqual(word.exampleKo, "곧 확정할 것이다.", "빈칸을 만든 예문과 같은 줄의 번역")
        XCTAssertEqual(word.posHints, ["verb"])
        XCTAssertEqual(word.meaningKo, "완성하다")
    }

    func testDataCheckFlagsMissingPieces() {
        XCTAssertEqual(WordDataCheck.issues(english: "finalize", meaningKo: "", exampleEn: "", exampleKo: ""), [.missingMeaning, .missingExample])
        XCTAssertEqual(WordDataCheck.issues(english: "finalize", meaningKo: "완성하다", exampleEn: "We completed the plan.", exampleKo: "완성했다"), [.exampleMissingWord])
        let ready = WordDataCheck.issues(english: "finalize", meaningKo: "완성하다", exampleEn: "We finalized the plan.", exampleKo: "확정했다")
        XCTAssertTrue(ready.isEmpty)
        XCTAssertTrue(WordDataCheck.isQuizReady(ready))
    }
}
