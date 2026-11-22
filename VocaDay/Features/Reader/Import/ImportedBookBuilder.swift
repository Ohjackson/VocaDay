import CryptoKit
import Foundation
import NaturalLanguage

/// 파서가 만든 중간 결과. 장 → 문단(문장으로 나누기 전 글).
nonisolated struct ImportDraft: Sendable, Equatable {
    var title: String
    var author: String?
    /// 파일에 적힌 언어. 없으면 본문으로 알아낸다.
    var declaredLanguage: String?
    var chapters: [ImportDraftChapter]
}

nonisolated struct ImportDraftChapter: Sendable, Equatable {
    var title: String
    var paragraphs: [String]
}

/// 가져오기 진행 상황. 0...1.
nonisolated struct ImportProgress: Sendable, Equatable {
    var fraction: Double
    var message: String
}

nonisolated enum BookImportError: LocalizedError, Equatable {
    case lockedPDF
    case unsupportedFormat
    case unreadable(String)
    case noText

    var errorDescription: String? {
        switch self {
        case .lockedPDF: "암호가 걸린 PDF는 가져올 수 없어요."
        case .unsupportedFormat: "PDF 파일만 가져올 수 있어요."
        case .unreadable(let detail): "파일을 읽지 못했어요. (\(detail))"
        case .noText: "가져올 본문을 찾지 못했어요."
        }
    }
}

/// 중간 결과를 계약 1 `BookDocument`로 만든다. 문장 나누기·언어·책 ID를 여기서 정한다.
nonisolated enum ImportedBookBuilder {
    static let idPrefix = "import-"

    static func makeBook(from draft: ImportDraft) throws -> BookDocument {
        let chapters = draft.chapters.compactMap { chapter -> ImportDraftChapter? in
            let paragraphs = chapter.paragraphs.map(normalizeWhitespace).filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { return nil }
            return ImportDraftChapter(title: normalizeWhitespace(chapter.title), paragraphs: paragraphs)
        }
        guard !chapters.isEmpty else { throw BookImportError.noText }

        let language = detectLanguage(chapters: chapters, declared: draft.declaredLanguage)
        let bookChapters = chapters.enumerated().map { index, chapter in
            BookChapter(
                title: chapter.title.isEmpty ? "Chapter \(index + 1)" : chapter.title,
                paragraphs: chapter.paragraphs.map { paragraph in
                    BookParagraph(sentences: splitSentences(paragraph, language: language).map {
                        BookSentence(text: $0, translation: nil)
                    })
                }.filter { !$0.sentences.isEmpty }
            )
        }
        let title = normalizeWhitespace(draft.title)
        return BookDocument(
            formatVersion: BookDocument.currentFormatVersion,
            id: bookID(chapters: chapters),
            language: language,
            title: title.isEmpty ? "가져온 책" : title,
            subtitle: nil,
            author: draft.author.map(normalizeWhitespace).flatMap { $0.isEmpty ? nil : $0 },
            level: nil,
            summary: nil,
            chapters: bookChapters,
            glossary: []
        )
    }

    /// 본문(문단 글) SHA-256 앞 16자리. 문장 나누기 전 글로 만들어 OS마다 문장 나누기가 조금 달라도 ID는 같다.
    /// 장 제목·책 제목은 넣지 않는다 (파일 이름으로 정한 제목이 기기마다 다를 수 있다).
    static func bookID(chapters: [ImportDraftChapter]) -> String {
        let body = chapters
            .map { $0.paragraphs.map(normalizeWhitespace).filter { !$0.isEmpty }.joined(separator: "\n") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let digest = SHA256.hash(data: Data(body.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return idPrefix + hex.prefix(16)
    }

    static func splitSentences(_ paragraph: String, language: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        tokenizer.setLanguage(NLLanguage(rawValue: language))
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let sentence = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return mergeFragments(sentences)
    }

    /// 문장 나누기가 잘못 끊은 곳을 다시 붙인다.
    /// - 따옴표·괄호만 남은 조각 ("”")
    /// - 소문자로 시작하는 조각: `“Who?”` + `said I.` → `“Who?” said I.`
    /// - 대사 뒤 짧은 말꼬리: `“Seven!”` + `I answered.`
    /// - 약어 뒤: `St.` + `John’s Wood`, `No.` + `7`
    static func mergeFragments(_ sentences: [String]) -> [String] {
        var result: [String] = []
        for sentence in sentences {
            guard let last = result.last else {
                result.append(sentence)
                continue
            }
            if shouldJoin(last, sentence) {
                result[result.count - 1] = last + " " + sentence
            } else if !sentence.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                result[result.count - 1] = last + sentence
            } else {
                result.append(sentence)
            }
        }
        return result
    }

    private static let joiningAbbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "mt", "messrs", "mme", "mlle", "col", "capt", "gen", "lt", "rev", "prof", "sgt", "fr", "hon",
    ]
    private static let closingQuotes = "”\"’'"

    private static func shouldJoin(_ previous: String, _ next: String) -> Bool {
        guard let first = next.first else { return false }
        if first.isLowercase { return true }
        // 약어로 끝난 앞 문장
        let lastWord = previous.split(separator: " ").last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "“\"‘'(")) } ?? ""
        if lastWord.hasSuffix(".") {
            let word = lastWord.dropLast().lowercased()
            if joiningAbbreviations.contains(word) { return true }
            if word == "no", first.isNumber { return true }
        }
        // “Seven!” I answered. / “No?” Holmes asked.
        if let end = previous.last, closingQuotes.contains(end), previous.dropLast().last.map({ "!?,".contains($0) }) == true,
           !"“\"‘'".contains(first), next.split(separator: " ").count <= 4, next.hasPrefix("I ") {
            return true
        }
        return false
    }

    static func detectLanguage(chapters: [ImportDraftChapter], declared: String?) -> String {
        if let declared, let code = Locale.Language(identifier: declared).languageCode?.identifier, !code.isEmpty {
            return code
        }
        var sample = ""
        outer: for chapter in chapters {
            for paragraph in chapter.paragraphs {
                sample += paragraph + "\n"
                if sample.count > 4000 { break outer }
            }
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return "en" }
        return Locale.Language(identifier: language.rawValue).languageCode?.identifier ?? language.rawValue
    }

    /// 줄바꿈·탭·여러 칸 공백을 한 칸으로. 줄 바꿈 없는 공백(nbsp)도 공백으로 본다.
    static func normalizeWhitespace(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "\u{00A0}" {
                pendingSpace = !result.isEmpty
            } else if scalar == "\u{00AD}" || scalar == "\u{200B}" || scalar == "\u{FEFF}" {
                continue // soft hyphen, zero-width space, BOM
            } else {
                if pendingSpace {
                    result.unicodeScalars.append(" ")
                    pendingSpace = false
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
