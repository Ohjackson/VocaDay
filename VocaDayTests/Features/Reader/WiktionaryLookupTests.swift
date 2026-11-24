import XCTest
@testable import VocaDay

@MainActor
final class WiktionaryLookupTests: XCTestCase {
    private let words = [
        "chain": "v. 줄에 매다",
        "silver": "n. 은 / adj. 은빛의 / v. 은도금하다",
        "whisper": "v. 속삭이다",
        "look forward to": "고대하다",
        "found": "v. 설립하다",
        "find": "v. 찾다",
    ]

    private func request(_ surface: String, lemmas: [String] = [], sentence: String = "") throws -> WordLookupRequest {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-first-week", withExtension: "json"))
        let book = try JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: url))
        return WordLookupRequest(surface: surface, lemmas: lemmas, sentence: sentence, book: book)
    }

    private func step(matching: Bool = true, partOfSpeech: String? = nil) -> WiktionaryLookupStep {
        let words = words
        return WiktionaryLookupStep(index: { words }, requiresMatchingPartOfSpeech: matching, partOfSpeech: { _, _ in partOfSpeech })
    }

    func testFindsLemmaWhenFormIsMissing() async throws {
        let lookup = try await step().lookup(request("whispered", lemmas: ["whisper"]))
        let found = try XCTUnwrap(lookup)
        XCTAssertEqual(found.headword, "whisper")
        XCTAssertEqual(found.surface, "whispered")
        XCTAssertEqual(found.meaningForSaving, "v. 속삭이다")
        XCTAssertEqual(found.source, .wiktionary)
    }

    func testMeaningForPartOfSpeechInSentenceComesFirst() async throws {
        let lookup = try await step(partOfSpeech: "adj.").lookup(request("silver"))
        XCTAssertEqual(lookup?.meaning, "adj. 은빛의 / n. 은 / v. 은도금하다")
    }

    func testSkipsVerbOnlyEntryInNounPosition() async throws {
        let skipped = try await step(partOfSpeech: "n.").lookup(request("chain"))
        XCTAssertNil(skipped)
        let fallback = try await step(matching: false, partOfSpeech: "n.").lookup(request("chain"))
        XCTAssertEqual(fallback?.meaning, "v. 줄에 매다")
        let unknown = try await step(partOfSpeech: nil).lookup(request("chain"))
        XCTAssertNotNil(unknown)
    }

    func testIrregularVerbUsesLemmaFirst() async throws {
        let verb = try await step(partOfSpeech: "v.").lookup(request("found", lemmas: ["find"]))
        XCTAssertEqual(verb?.headword, "find")
        let unknown = try await step(partOfSpeech: nil).lookup(request("found", lemmas: ["find"]))
        XCTAssertEqual(unknown?.headword, "found")
    }

    /// lemma 모델이 없는 환경에서도 흔한 불규칙 변화를 되돌린다.
    func testWordFormsCoverIrregulars() {
        for (form, lemma) in ["held": "hold", "took": "take", "children": "child", "feet": "foot", "was": "be"] {
            XCTAssertEqual(EnglishWordForms.shared[form], lemma)
            XCTAssertTrue(EnglishLemmatizer().lemmas(of: form, in: form).contains(lemma))
        }
    }

    func testFindsIdiom() async throws {
        let lookup = try await step(matching: false).lookup(request("look forward to"))
        XCTAssertEqual(lookup?.meaning, "고대하다")
    }

    func testTranslationMissStillUsesMismatchedEntry() async throws {
        let words = words
        let pipeline = EnglishWordLookup.pipeline(
            bundledWords: { [:] },
            wiktionary: { words },
            usesTranslation: false,
            usesSystemDictionary: false
        )
        guard case .found(let result) = await pipeline.lookup(try request("chain", sentence: "She held the silver chain.")) else {
            return XCTFail("못 찾음")
        }
        XCTAssertEqual(result.source, .wiktionary)
    }

    // MARK: - 예문

    func testExamplesFollowSenses() async throws {
        let step = WiktionaryLookupStep(
            index: { ["hold": "v. 갖고 있다; 보관하다; 품다 / n. 쥐기"] },
            examples: { _ in [
                WordMeaningExample(meaning: "쥐기", english: "Take hold of it.", korean: "그것을 잡아라."),
                WordMeaningExample(meaning: "없는 뜻", english: "Hold.", korean: "잡다."),
                WordMeaningExample(meaning: "보관하다", english: "I'll hold it for you.", korean: "맡아 둘게."),
            ] },
            requiresMatchingPartOfSpeech: false,
            partOfSpeech: { _, _ in nil }
        )
        let lookup = try await step.lookup(request("hold"))
        let found = try XCTUnwrap(lookup)
        XCTAssertEqual(found.examples.map(\.meaning), ["보관하다", "쥐기"])
        XCTAssertEqual(found.meaningForSaving, "v. 갖고 있다; 보관하다 / n. 쥐기")
    }

    func testBundledExamplesAreFound() {
        let hold = WiktionaryDictionary.examples(for: "hold")
        XCTAssertTrue(hold.contains { $0.english == "One man is holding a box." })
        XCTAssertTrue(WiktionaryDictionary.examples(for: "zzz").isEmpty)
    }

    /// 위키낱말사전에 예문이 없는 뜻은 앱 안의 문장에서.
    func testAppExamplesFillMissingSenses() throws {
        if AppMeaningExamples.shared.examples.isEmpty {
            throw XCTSkip("MeaningExamples.json 이 없어요 (저장소에 포함하지 않음).")
        }
        XCTAssertGreaterThan(AppMeaningExamples.shared.examples.count, 500)
        XCTAssertNil(WiktionaryDictionary.shared.examples["coat"])
        XCTAssertFalse(WiktionaryDictionary.examples(for: "coat").isEmpty)
    }

    /// 책 사전의 뜻에도 같은 뜻의 예문이 붙고, 지금 읽는 문장은 빠진다.
    func testGlossaryMeaningBorrowsExample() async throws {
        let example = WordMeaningExample(meaning: "할당하다, 나누어 주다", english: "He allocated the funds.", korean: "그는 자금을 할당했다.")
        let second = WordMeaningExample(meaning: "배정하다", english: "Seats were allocated.", korean: "좌석이 배정되었다.")
        let other = WordMeaningExample(meaning: "다른 뜻", english: "Allocate.", korean: "다른.")
        func examples(reading sentence: String) async throws -> [WordMeaningExample] {
            let pipeline = EnglishWordLookup.pipeline(
                bundledWords: { [:] },
                wiktionary: { [:] },
                wiktionaryExamples: { $0 == "allocate" ? [other, example, second] : [] },
                usesTranslation: false,
                usesSystemDictionary: false
            )
            guard case .found(let result) = await pipeline.lookup(try request("allocated", sentence: sentence)) else { return [] }
            XCTAssertEqual(result.source, .bookGlossary)
            return result.examples
        }
        let found = try await examples(reading: "Her desk was allocated.")
        XCTAssertEqual(found.map(\.english), ["He allocated the funds."])
        XCTAssertEqual(found.first?.meaning, "할당하다, 배정하다")
        let same = try await examples(reading: "He allocated the funds.")
        XCTAssertEqual(same.map(\.english), ["Seats were allocated."])
    }

    func testBundledPackShowsItsOwnExample() async throws {
        if BundledWordIndex.shared.isEmpty {
            throw XCTSkip("BundledWords.json 이 없어요 (저장소에 포함하지 않음).")
        }
        let word = try XCTUnwrap(BundledWordIndex.shared.values.first { !$0.exampleEn.isEmpty && !$0.exampleKo.isEmpty })
        let lookup = try await BundledPackLookupStep(index: { BundledWordIndex.shared }).lookup(request(word.english.normalizedEnglish))
        XCTAssertEqual(lookup?.examples, WordMeaningExample.whole(english: word.exampleEn, korean: word.exampleKo))
        XCTAssertEqual(lookup?.examples.count, 1)
    }

    /// 예문은 모두 사전에 있는 뜻에 붙고, 영어·한국어가 다 있다.
    func testBundledExamplesMatchSenses() throws {
        let dictionary = try XCTUnwrap(WiktionaryDictionary.load())
        XCTAssertGreaterThan(dictionary.examples.count, 1_500)
        for source in [dictionary.examples, AppMeaningExamples.shared.examples] {
            for (word, senses) in source {
                let segments = WiktionaryLookupStep.segments(try XCTUnwrap(dictionary.words[word], word))
                XCTAssertEqual(
                    WiktionaryLookupStep.sorted(
                        senses.map { WordMeaningExample(meaning: $0.key, english: "e", korean: "k") },
                        by: segments
                    ).count,
                    senses.count,
                    word
                )
                for pair in senses.values {
                    XCTAssertEqual(pair.count, 2, word)
                    XCTAssertFalse(pair[0].isEmpty, word)
                    XCTAssertTrue(pair[1].unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, word)
                }
            }
        }
    }

    func testEmphasisFindsInflectedForm() {
        for (word, sentence, form) in [
            ("hold", "One man is holding a box.", "holding"),
            ("hold", "She held the chain.", "held"),
            ("coat", "She put on her coat.", "coat"),
        ] {
            let text = WordHighlighter.emphasized(word, in: sentence)
            let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(text[$0.range].characters) }
            XCTAssertEqual(bold, [form])
        }
    }

    func testWholeWordExampleNeedsBothLanguages() {
        XCTAssertEqual(
            WordMeaningExample.whole(english: "A.\nB.", korean: "가.\n나."),
            [WordMeaningExample(meaning: nil, english: "A.", korean: "가.")]
        )
        XCTAssertTrue(WordMeaningExample.whole(english: "A.", korean: " ").isEmpty)
    }

    /// 앱에 들어 있는 파일: 출처가 적혀 있고, 뜻은 모두 카드가 나눌 수 있는 모양이다.
    func testBundledFileIsWellFormed() throws {
        let dictionary = try XCTUnwrap(WiktionaryDictionary.load())
        XCTAssertEqual(dictionary.license, "CC BY-SA 4.0")
        XCTAssertFalse(dictionary.dumpDate.isEmpty)
        XCTAssertGreaterThan(dictionary.words.count, 14_000)
        for (word, meaning) in dictionary.words {
            XCTAssertEqual(word, word.lowercased())
            XCTAssertTrue(meaning.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "\(word): \(meaning)")
            XCTAssertFalse(meaning.contains("{{") || meaning.contains("[") || meaning.contains("<"), "\(word): \(meaning)")
            guard !word.contains(" ") else { continue }
            for segment in WiktionaryLookupStep.segments(meaning) {
                XCTAssertNotNil(segment.range(of: #"^(n|v|adj|adv|prep|pron|conj|interj)\. "#, options: .regularExpression), "\(word): \(meaning)")
            }
            let lines = MeaningLines(WordLookupResult(headword: word, surface: word, partOfSpeech: nil, meaning: meaning, source: .wiktionary))
            XCTAssertEqual(lines.lines.count, WiktionaryLookupStep.segments(meaning).count, "\(word): \(meaning)")
        }
        XCTAssertEqual(WiktionaryDictionary.pageURL(for: "look after")?.absoluteString, "https://ko.wiktionary.org/wiki/look_after")
    }
}
