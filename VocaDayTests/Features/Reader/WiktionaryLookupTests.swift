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
