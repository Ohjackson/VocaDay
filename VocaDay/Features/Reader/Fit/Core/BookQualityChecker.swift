import Foundation

/// 책 데이터 품질 경고: 번역 누락, 아주 긴 문장, 끝맺음 없는 문장, 깨진 글자(OCR), 책 사전 `firstPosition` 오류.
nonisolated struct BookQualityChecker: Sendable {
    var rules: FitLanguageRules
    var lemmatizer: any Lemmatizer
    /// 경고마다 남길 위치 수.
    var positionLimit = 20

    struct Result: Sendable {
        var warnings: [BookQualityWarning]
        var garbledRatio: Double
    }

    func warnings(for book: BookDocument, tokensByPosition: [ReadingPosition: [FitToken]]? = nil) -> Result {
        var missing: [ReadingPosition] = []
        var long: [ReadingPosition] = []
        var unterminated: [ReadingPosition] = []
        var garbledSentences: [ReadingPosition] = []
        var garbledCharacters = 0
        var visibleCharacters = 0

        let sentences = book.fitSentences
        for (position, sentence) in sentences {
            let text = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if (sentence.translation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append(position)
            }
            let tokenCount = tokensByPosition?[position]?.count ?? lemmatizer.tokens(in: text).count
            if tokenCount >= rules.longSentenceTokenCount {
                long.append(position)
            }
            if !text.isEmpty, !isTerminated(text), !rules.allowsUnterminated(text) {
                unterminated.append(position)
            }

            var bad = 0
            for character in text where !character.isWhitespace {
                visibleCharacters += 1
                if character == "\u{FFFD}" || !rules.isExpectedCharacter(character) { bad += 1 }
            }
            if bad > 0 {
                garbledCharacters += bad
                garbledSentences.append(position)
            }
        }

        let glossary = glossaryProblems(in: book, sentences: sentences)
        let ratio = visibleCharacters == 0 ? 0 : Double(garbledCharacters) / Double(visibleCharacters)

        let warnings = [
            warning(.missingTranslation, missing),
            warning(.longSentence, long),
            warning(.unterminatedSentence, unterminated),
            warning(.garbledText, garbledSentences, details: garbledCharacters > 0 ? [String(format: "%.2f%%", ratio * 100)] : []),
            warning(.glossaryPositionInvalid, glossary.invalid.map(\.1), details: glossary.invalid.map(\.0)),
            warning(.glossaryPositionNotFirst, glossary.notFirst.map(\.1), details: glossary.notFirst.map(\.0)),
        ]
        return Result(warnings: warnings, garbledRatio: ratio)
    }

    private func warning(_ kind: BookQualityWarning.Kind, _ positions: [ReadingPosition], details: [String] = []) -> BookQualityWarning {
        BookQualityWarning(kind: kind, count: positions.count, positions: Array(positions.prefix(positionLimit)), details: Array(details.prefix(positionLimit)))
    }

    private func isTerminated(_ text: String) -> Bool {
        var last = text.last
        var rest = Substring(text)
        while let character = last, rules.closingMarks.contains(character) {
            rest = rest.dropLast()
            last = rest.last
        }
        guard let last else { return false }
        return rules.sentenceTerminators.contains(last)
    }

    // MARK: 책 사전

    /// invalid: 위치가 없거나, 범위 밖이거나, 그 문장에 표제어 모양이 없다.
    /// notFirst: 위치는 맞지만 더 앞 문장에 같은 모양이 나온다.
    private func glossaryProblems(in book: BookDocument, sentences: [(position: ReadingPosition, sentence: BookSentence)]) -> (invalid: [(String, ReadingPosition)], notFirst: [(String, ReadingPosition)]) {
        var invalid: [(String, ReadingPosition)] = []
        var notFirst: [(String, ReadingPosition)] = []
        let positions = sentences.map(\.position)
        let normalized = Dictionary(uniqueKeysWithValues: sentences.map { ($0.position, Self.wordString($0.sentence.text, normalize: lemmatizer.normalize)) })

        for entry in book.glossary {
            let forms = Set(([entry.lemma] + entry.forms).map { Self.wordString($0, normalize: lemmatizer.normalize).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            guard let position = entry.firstPosition else {
                invalid.append((entry.lemma, .start))
                continue
            }
            guard let text = normalized[position] else {
                invalid.append((entry.lemma, position))
                continue
            }
            guard forms.contains(where: { text.contains(" \($0) ") }) else {
                invalid.append((entry.lemma, position))
                continue
            }
            if let earlier = positions.first(where: { candidate in
                candidate < position && forms.contains { (normalized[candidate] ?? "").contains(" \($0) ") }
            }) {
                notFirst.append((entry.lemma, earlier))
            }
        }
        return (invalid, notFirst)
    }

    /// " word word " 모양. 소유격 's 를 떼고, 글자·숫자·하이픈·아포스트로피 밖은 공백으로 바꾼다.
    static func wordString(_ text: String, normalize: (String) -> String) -> String {
        let lowered = normalize(text)
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "'" {
                scalars.append(scalar)
            } else {
                scalars.append(" ")
            }
        }
        let words = String(scalars).split(separator: " ").map { word -> String in
            var word = String(word)
            if word.hasSuffix("'s") { word.removeLast(2) }
            return word.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
        }.filter { !$0.isEmpty }
        return " " + words.joined(separator: " ") + " "
    }
}
