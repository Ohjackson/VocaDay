import XCTest
@testable import VocaDay

/// samples/sample_words.json 으로 samples/validate_reference.py 와 같은 결과인지 확인한다.
final class EntryValidatorTests: XCTestCase {
    private struct Sample {
        var term: String
        var entry: [String: Any]
    }

    private func loadSamples() throws -> (valid: [Sample], invalid: [(why: String, patch: [String: Any])]) {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sample_words", withExtension: "json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let valid = try XCTUnwrap(root["valid"] as? [[String: Any]]).map { item in
            Sample(
                term: (item["input"] as? [String: Any])?["term"] as? String ?? "",
                entry: item["entry"] as? [String: Any] ?? [:]
            )
        }
        let invalid = try XCTUnwrap(root["invalid"] as? [[String: Any]]).map { item in
            (why: item["why"] as? String ?? "", patch: item["entry_patch"] as? [String: Any] ?? [:])
        }
        return (valid, invalid)
    }

    private func decode(_ object: [String: Any]) throws -> WordEntry {
        try JSONDecoder().decode(WordEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testAllEightValidSamplesPass() throws {
        let samples = try loadSamples().valid
        XCTAssertEqual(samples.count, 8)
        for sample in samples {
            let entry = try decode(sample.entry)
            XCTAssertEqual(EntryValidator.validate(entry, requestedTerm: sample.term).map(\.code), [], sample.term)
        }
    }

    func testAllSevenInvalidSamplesAreRejectedWithExpectedCode() throws {
        let samples = try loadSamples()
        XCTAssertEqual(samples.invalid.count, 7)
        let baseByTerm = Dictionary(uniqueKeysWithValues: samples.valid.map { ($0.entry["term"] as? String ?? "", $0.entry) })

        for invalid in samples.invalid {
            let term = try XCTUnwrap(invalid.patch["term"] as? String)
            var object = try XCTUnwrap(baseByTerm[term])
            object.merge(invalid.patch) { _, patched in patched }
            let entry = try decode(object)

            // "… (restore)" → "restore"
            let expected = String(invalid.why.split(separator: "(").last?.dropLast() ?? "")
            let codes = EntryValidator.validate(entry, requestedTerm: term).map(\.code)
            // validate_reference.py 출력과 동일하게 해당 코드 하나만 나와야 한다.
            XCTAssertEqual(codes, [expected], invalid.why)
        }
    }

    func testEmptyFieldsShortCircuit() {
        let codes = EntryValidator.validate(WordEntry(term: "abandon"), requestedTerm: "abandon").map(\.code)
        XCTAssertEqual(codes.first, "empty:pos")
        XCTAssertFalse(codes.contains("restore"))
    }

    func testTermMismatchAndCorrectionMessage() throws {
        let entry = try decode(loadSamples().valid[0].entry)
        let errors = EntryValidator.validate(entry, requestedTerm: "abandonment")
        XCTAssertEqual(errors.map(\.code), ["term_mismatch"])
        XCTAssertTrue(EntryValidator.correctionMessage(for: errors).contains("[term_mismatch]"))
    }

    func testMeaningLengthCountsCharactersLikePython() throws {
        var entry = try decode(loadSamples().valid[0].entry)
        entry.meaningKo = String(repeating: "가", count: 20)
        XCTAssertFalse(EntryValidator.validate(entry, requestedTerm: "abandon").contains(.meaningLength))
        entry.meaningKo = String(repeating: "가", count: 21)
        XCTAssertTrue(EntryValidator.validate(entry, requestedTerm: "abandon").contains(.meaningLength))
    }
}
