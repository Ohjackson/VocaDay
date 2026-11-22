import Foundation
import SwiftData

// 리더 북마크·마지막 읽은 위치. 앱 컨테이너(CloudKit private DB)로 기기 사이에 동기화된다.
// CloudKit 조건: 모든 속성에 기본값, unique 제약 없음, 관계 없음.

/// 책 안의 북마크 한 개. 같은 `id`가 여러 행이면 하나로 본다.
@Model
final class ReaderBookmarkRecord {
    var id: UUID = UUID()
    var bookID: String = ""
    var chapter: Int = 0
    var paragraph: Int = 0
    var sentence: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), bookID: String, position: ReadingPosition, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.chapter = position.chapter
        self.paragraph = position.paragraph
        self.sentence = position.sentence
        self.note = note
        self.createdAt = createdAt
    }

    var position: ReadingPosition {
        ReadingPosition(chapter: chapter, paragraph: paragraph, sentence: sentence)
    }

    var bookmark: ReaderBookmark {
        ReaderBookmark(id: id, bookID: bookID, position: position, note: note, createdAt: createdAt)
    }
}

/// 책마다 마지막으로 읽은 위치. 책 하나에 한 행이 목표지만, 두 기기가 따로 만들면 행이 여럿이 된다.
/// 그때는 `updatedAt`이 가장 늦은 행을 쓰고 나머지는 지운다 (`ReaderPositionMerge`).
@Model
final class ReaderPositionRecord {
    /// 같은 시각에 쓰인 행끼리 어느 기기에서든 같은 행을 남기려고 둔다.
    var id: UUID = UUID()
    var bookID: String = ""
    var chapter: Int = 0
    var paragraph: Int = 0
    var sentence: Int = 0
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), bookID: String, position: ReadingPosition, updatedAt: Date = Date()) {
        self.id = id
        self.bookID = bookID
        self.chapter = position.chapter
        self.paragraph = position.paragraph
        self.sentence = position.sentence
        self.updatedAt = updatedAt
    }

    var position: ReadingPosition {
        get { ReadingPosition(chapter: chapter, paragraph: paragraph, sentence: sentence) }
        set {
            chapter = newValue.chapter
            paragraph = newValue.paragraph
            sentence = newValue.sentence
        }
    }
}

/// 중복 행을 고르는 규칙. 모든 기기가 같은 행을 남기도록 순서가 정해져 있다.
enum ReaderPositionMerge {
    /// 남길 행이 앞서면 true: `updatedAt`이 늦은 쪽, 같으면 `id` 문자열이 큰 쪽.
    static func isPreferred(_ lhs: ReaderPositionRecord, over rhs: ReaderPositionRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    /// 책별로 남길 행과 지울 행을 나눈다.
    static func split(_ records: [ReaderPositionRecord]) -> (keep: [String: ReaderPositionRecord], discard: [ReaderPositionRecord]) {
        var keep: [String: ReaderPositionRecord] = [:]
        var discard: [ReaderPositionRecord] = []
        for record in records {
            if let current = keep[record.bookID] {
                if isPreferred(record, over: current) {
                    discard.append(current)
                    keep[record.bookID] = record
                } else {
                    discard.append(record)
                }
            } else {
                keep[record.bookID] = record
            }
        }
        return (keep, discard)
    }
}

enum ReaderBookmarkMerge {
    /// 같은 `id` 행은 하나로 본다 (먼저 만든 행). 위치 순서, 같은 위치면 만든 순서.
    static func unique(_ records: [ReaderBookmarkRecord]) -> [ReaderBookmark] {
        var byID: [UUID: ReaderBookmark] = [:]
        for record in records {
            let mark = record.bookmark
            if let existing = byID[mark.id], existing.createdAt <= mark.createdAt { continue }
            byID[mark.id] = mark
        }
        return sorted(Array(byID.values))
    }

    static func sorted(_ marks: [ReaderBookmark]) -> [ReaderBookmark] {
        marks.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
