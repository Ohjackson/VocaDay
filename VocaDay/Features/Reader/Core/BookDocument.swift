import Foundation

// 리더 공통 형식: 책.
// 앱 모델(VocaWord 등)을 쓰지 않는다. 나중에 일본어 앱과 함께 쓰는 패키지로 옮긴다.

/// 앱 안 책 한 권. `Books/<id>.json` 하나가 한 권이다.
nonisolated struct BookDocument: Codable, Hashable, Sendable, Identifiable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    /// 기기 사이에서 같은 값. 북마크·읽은 위치가 이 값으로 책을 가리킨다. 예: "toeic-short-001"
    var id: String
    /// BCP-47 언어 코드. 지금은 "en", 일본어 앱은 "ja".
    var language: String
    var title: String
    /// 한국어 부제. 예: "신입 사원 민지의 첫 출장"
    var subtitle: String?
    var author: String?
    /// 예: "TOEIC 600~750"
    var level: String?
    /// 한국어 소개 한두 문장.
    var summary: String?
    var chapters: [BookChapter]
    /// 책 안 단어 뜻. 단어를 누르면 이것부터 찾는다.
    var glossary: [GlossaryEntry]
}

nonisolated struct BookChapter: Codable, Hashable, Sendable {
    var title: String
    var paragraphs: [BookParagraph]
}

nonisolated struct BookParagraph: Codable, Hashable, Sendable {
    var sentences: [BookSentence]
}

/// 읽기·듣기·하이라이트·북마크의 최소 단위.
nonisolated struct BookSentence: Codable, Hashable, Sendable {
    var text: String
    /// 한국어 번역.
    var translation: String?
}

nonisolated struct GlossaryEntry: Codable, Hashable, Sendable {
    /// 원형. 예: "allocate"
    var lemma: String
    /// 본문에 실제로 나오는 모양, 소문자. 예: ["allocate", "allocated"]
    var forms: [String]
    /// 예: "v."
    var partOfSpeech: String
    /// 한국어 뜻. 예: "할당하다, 배분하다"
    var meaning: String
    var note: String?
    /// 처음 나온 문장. 단어를 추가할 때 예문으로 쓴다.
    var firstPosition: ReadingPosition?
}

/// 책 안의 문장 위치. 페이지가 아니라 문장으로 가리켜서 글자 크기·기기가 달라도 같은 곳이다.
nonisolated struct ReadingPosition: Codable, Hashable, Sendable, Comparable {
    var chapter: Int
    var paragraph: Int
    var sentence: Int

    static let start = ReadingPosition(chapter: 0, paragraph: 0, sentence: 0)

    static func < (lhs: ReadingPosition, rhs: ReadingPosition) -> Bool {
        (lhs.chapter, lhs.paragraph, lhs.sentence) < (rhs.chapter, rhs.paragraph, rhs.sentence)
    }
}

extension BookDocument {
    func sentence(at position: ReadingPosition) -> BookSentence? {
        guard chapters.indices.contains(position.chapter) else { return nil }
        let paragraphs = chapters[position.chapter].paragraphs
        guard paragraphs.indices.contains(position.paragraph) else { return nil }
        let sentences = paragraphs[position.paragraph].sentences
        guard sentences.indices.contains(position.sentence) else { return nil }
        return sentences[position.sentence]
    }

    /// 본문 순서대로 모든 문장 위치.
    var positions: [ReadingPosition] {
        chapters.indices.flatMap { c in
            chapters[c].paragraphs.indices.flatMap { p in
                chapters[c].paragraphs[p].sentences.indices.map {
                    ReadingPosition(chapter: c, paragraph: p, sentence: $0)
                }
            }
        }
    }

    /// 본문에 나온 모양(대소문자 무시)으로 책 사전을 찾는다.
    func glossaryEntry(forSurface surface: String) -> GlossaryEntry? {
        let key = surface.lowercased()
        return glossary.first { $0.forms.contains(key) || $0.lemma.lowercased() == key }
    }
}
