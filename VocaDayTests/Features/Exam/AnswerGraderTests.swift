import XCTest
@testable import VocaDay

final class AnswerGraderTests: XCTestCase {
    private let abandon: QuizWord = {
        var word = ExamFixtures.verb(
            "abandon", past: "abandoned", ing: "abandoning", third: "abandons",
            meaning: "버리다", clozeForm: "past", nearMiss: ["leave", "desert", "throw away"]
        )
        word.termVariants = []
        return word
    }()

    func testNormalization() {
        XCTAssertEqual(ExamText.normalize("  Gave   UP. "), "gave up")
        XCTAssertEqual(ExamText.normalize("don’t!?"), "don't")
    }

    func testClozeAcceptsAnswerAndAcceptedSpellings() {
        var word = ExamFixtures.verb("travel", past: "traveled", ing: "traveling", third: "travels", meaning: "여행하다")
        word.clozeAccepted = ["travelled"]
        XCTAssertEqual(AnswerGrader.gradeCloze("Traveled", word: word), .correct)
        XCTAssertEqual(AnswerGrader.gradeCloze("travelled", word: word), .correct)
    }

    func testTypoOnlyForLongAnswersAndDistanceOne() {
        XCTAssertEqual(AnswerGrader.gradeKoToEn("abandn", word: abandon), .typo(expected: "abandon"))
        // 거리 2: 정답은 아니지만 떠올린 것으로 보고 힌트와 함께 한 번 더.
        XCTAssertEqual(AnswerGrader.gradeKoToEn("abndn", word: abandon), .nearMiss(message: "철자가 조금 달라요. a로 시작하는 7글자예요. 한 번 더 써 보세요"))
        XCTAssertEqual(AnswerGrader.gradeKoToEn("abndn", word: abandon, isRetry: true), .wrong(expected: "abandon"))
        XCTAssertEqual(AnswerGrader.gradeKoToEn("xyz", word: abandon), .wrong(expected: "abandon"))

        // 9글자 이상은 두 글자 오타까지 정답.
        let long = ExamFixtures.plain("negotiate", meaning: "협상하다")
        XCTAssertEqual(AnswerGrader.gradeKoToEn("negociat", word: long), .typo(expected: "negotiate"))

        let short = ExamFixtures.plain("cat", meaning: "고양이")
        XCTAssertEqual(AnswerGrader.gradeKoToEn("cap", word: short), .wrong(expected: "cat"), "4글자 이하는 오타 허용 안 함")

        var strict = GradingOptions.standard
        strict.allowsTypo = false
        XCTAssertFalse(AnswerGrader.gradeKoToEn("abandn", word: abandon, options: strict).isCorrect, "오타 허용을 끄면 정답 처리하지 않는다")
    }

    func testClozeOtherInflectionIsNearMissOnce() {
        let first = AnswerGrader.gradeCloze("abandon", word: abandon)
        XCTAssertEqual(first, .nearMiss(message: "형태가 달라요 (과거형으로 써 보세요)"))
        XCTAssertFalse(first.isFinal)
        XCTAssertEqual(AnswerGrader.gradeCloze("abandon", word: abandon, isRetry: true), .wrong(expected: "abandoned"))
        XCTAssertEqual(AnswerGrader.gradeCloze("abandoned", word: abandon, isRetry: true), .correct)
    }

    func testOtherInflectionIsNeverTreatedAsTypo() {
        // abandons 와 abandon 은 거리 1이지만 다른 활용형이므로 오타 정답이 아니다.
        var noRetry = GradingOptions.standard
        noRetry.allowsNearMissRetry = false
        XCTAssertEqual(AnswerGrader.gradeKoToEn("abandons", word: abandon, options: noRetry), .wrong(expected: "abandon"))
    }

    func testKoToEnSynonymIsNearMissWithInitialHint() {
        XCTAssertEqual(
            AnswerGrader.gradeKoToEn("desert", word: abandon),
            .nearMiss(message: "뜻은 맞지만 연습 중인 단어가 아니에요 (a로 시작)")
        )
        XCTAssertEqual(AnswerGrader.gradeKoToEn("abandoned", word: abandon), .nearMiss(message: "기본형으로 써 주세요"))
        XCTAssertEqual(AnswerGrader.gradeKoToEn("desert", word: abandon, isRetry: true), .wrong(expected: "abandon"))
    }

    func testKoToEnAcceptsTermVariants() {
        var colour = ExamFixtures.plain("color", meaning: "색")
        colour.termVariants = ["colour"]
        XCTAssertEqual(AnswerGrader.gradeKoToEn("Colour", word: colour), .correct)
    }

    func testUnenrichedWordGradesAgainstTerm() {
        let word = ExamFixtures.plain("seeing someone", meaning: "사귀다")
        XCTAssertEqual(AnswerGrader.gradeKoToEn("Seeing  someone", word: word), .correct)
        XCTAssertEqual(AnswerGrader.gradeKoToEn("", word: word), .wrong(expected: "seeing someone"))
    }

    func testHints() {
        XCTAssertEqual(AnswerGrader.hint(for: "abandoned", style: .firstLetters), "a _ _ _ _ _ _ _ _")
        XCTAssertEqual(AnswerGrader.hint(for: "gave up", style: .firstLetters), "g _ _ _   u _")
        XCTAssertEqual(AnswerGrader.hint(for: "abandoned", style: .length), "(9글자)")
        XCTAssertEqual(AnswerGrader.hint(for: "gave up", style: .length), "(4·2글자)")
        XCTAssertEqual(AnswerGrader.hint(for: "gave up", style: .none), "")
    }

    func testKoreanParticle() {
        XCTAssertEqual(AnswerGrader.josaEuro("과거분사"), "로")
        XCTAssertEqual(AnswerGrader.josaEuro("과거형"), "으로")
    }
}
