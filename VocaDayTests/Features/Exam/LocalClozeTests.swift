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
        XCTAssertEqual(LocalCloze.build(term: "be supposed to", example: "Staff are supposed to sign in.")?.answer, "are supposed to")
        XCTAssertEqual(LocalCloze.build(term: "be aware of", example: "He is aware of the risk.")?.answer, "is aware of")
        XCTAssertEqual(LocalCloze.build(term: "overhear", example: "I overheard the news.")?.answer, "overheard")
        XCTAssertEqual(LocalCloze.build(term: "to one's advantage", example: "It worked to her advantage.")?.answer, "to her advantage")
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

    func testRotatesExampleLinesBySeed() {
        let example = "1. Please keep a record of all expenses.\n2. The assistant recorded the minutes."
        let translation = "1. 경비를 모두 기록해 두세요.\n2. 비서가 회의록을 기록했다."
        XCTAssertEqual(LocalCloze.buildAll(term: "record", example: example).map(\.answer), ["record", "recorded"])

        let meaning = "n. 기록 / v. 기록하다"
        let first = QuizWord.local(term: "record", meaningKo: meaning, exampleEn: example, exampleKo: translation, exampleSeed: 0)
        XCTAssertEqual(first.clozeSentence, "Please keep a <> of all expenses.")
        XCTAssertEqual(first.exampleKo, "경비를 모두 기록해 두세요.")

        let second = QuizWord.local(term: "record", meaningKo: meaning, exampleEn: example, exampleKo: translation, exampleSeed: 1)
        XCTAssertEqual(second.clozeSentence, "The assistant <> the minutes.")
        XCTAssertEqual(second.exampleKo, "비서가 회의록을 기록했다.")

        let third = QuizWord.local(term: "record", meaningKo: meaning, exampleEn: example, exampleKo: translation, exampleSeed: 2)
        XCTAssertEqual(third.clozeSentence, first.clozeSentence, "줄 수로 나눈 나머지로 돌아간다")
    }

    func testRotationSkipsLinesWithoutWord() {
        let example = "1. The plan was approved.\n2. They will finalize it soon."
        for seed in 0..<3 {
            let word = QuizWord.local(term: "finalize", meaningKo: "v. 완성하다", exampleEn: example, exampleKo: "1. 승인됐다.\n2. 곧 확정한다.", exampleSeed: seed)
            XCTAssertEqual(word.example, "They will finalize it soon.")
        }
    }

    func testDataCheckFlagsMultiLineExamples() {
        let partial = WordDataCheck.issues(english: "finalize", meaningKo: "v. 완성하다", exampleEn: "1. The plan was approved.\n2. They will finalize it.", exampleKo: "1. 승인됐다.\n2. 확정한다.")
        XCTAssertEqual(partial, [.someExampleLinesMissingWord])
        XCTAssertTrue(WordDataCheck.isQuizReady(partial), "한 줄이라도 빈칸이 되면 시험 준비됨")

        let mismatch = WordDataCheck.issues(english: "record", meaningKo: "n. 기록 / v. 기록하다", exampleEn: "1. Keep a record.\n2. She recorded it.", exampleKo: "기록해 두세요.")
        XCTAssertEqual(mismatch, [.exampleTranslationLineMismatch])

        let pairs = ExamText.examplePairs(en: "1. Keep a record.\n2. She recorded it.", ko: "1. 기록해 두세요.")
        XCTAssertEqual(pairs.map(\.en), ["Keep a record.", "She recorded it."])
        XCTAssertEqual(pairs.map(\.ko), ["기록해 두세요.", ""])
    }

    func testDataCheckFlagsMissingPieces() {
        XCTAssertEqual(WordDataCheck.issues(english: "finalize", meaningKo: "", exampleEn: "", exampleKo: ""), [.missingMeaning, .missingExample])
        XCTAssertEqual(WordDataCheck.issues(english: "finalize", meaningKo: "완성하다", exampleEn: "We completed the plan.", exampleKo: "완성했다"), [.exampleMissingWord])
        let ready = WordDataCheck.issues(english: "finalize", meaningKo: "완성하다", exampleEn: "We finalized the plan.", exampleKo: "확정했다")
        XCTAssertTrue(ready.isEmpty)
        XCTAssertTrue(WordDataCheck.isQuizReady(ready))
    }
}
