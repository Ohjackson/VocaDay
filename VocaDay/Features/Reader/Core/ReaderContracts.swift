import Foundation
import Observation
import SwiftUI

// 리더 공통 계약 2: 작업 사이의 연결 지점.
// 이 파일은 VocaDay/Features/Reader/Core/ReaderContracts.swift 에 그대로 복사한다. 작업자는 고치지 않는다.

// MARK: - 북마크·읽은 위치 (구현: Reader/Sync)

nonisolated struct ReaderBookmark: Hashable, Sendable, Identifiable {
    var id: UUID
    var bookID: String
    var position: ReadingPosition
    /// 사용자가 남긴 짧은 메모. 없으면 "".
    var note: String
    var createdAt: Date
}

/// 리더 화면이 쓰는 저장소. 구현은 `@Observable` 이어야 하고, 값이 바뀌면 화면이 다시 그려져야 한다.
protocol ReadingStore: AnyObject, Observable {
    func lastPosition(bookID: String) -> ReadingPosition?
    func saveLastPosition(_ position: ReadingPosition, bookID: String)
    /// 위치 순서대로.
    func bookmarks(bookID: String) -> [ReaderBookmark]
    @discardableResult
    func addBookmark(at position: ReadingPosition, bookID: String, note: String) -> ReaderBookmark
    func removeBookmark(id: UUID)
}

/// 미리보기·테스트용 기기 메모리 저장소.
@Observable
final class InMemoryReadingStore: ReadingStore {
    private var positions: [String: ReadingPosition] = [:]
    private var marks: [ReaderBookmark] = []

    init() {}

    func lastPosition(bookID: String) -> ReadingPosition? { positions[bookID] }

    func saveLastPosition(_ position: ReadingPosition, bookID: String) { positions[bookID] = position }

    func bookmarks(bookID: String) -> [ReaderBookmark] {
        marks.filter { $0.bookID == bookID }.sorted { $0.position < $1.position }
    }

    @discardableResult
    func addBookmark(at position: ReadingPosition, bookID: String, note: String) -> ReaderBookmark {
        let mark = ReaderBookmark(id: UUID(), bookID: bookID, position: position, note: note, createdAt: Date())
        marks.append(mark)
        return mark
    }

    func removeBookmark(id: UUID) { marks.removeAll { $0.id == id } }
}

private struct ReadingStoreKey: EnvironmentKey {
    static let defaultValue: any ReadingStore = InMemoryReadingStore()
}

extension EnvironmentValues {
    /// 앱 루트에서 CloudKit 동기화 저장소(`SwiftDataReadingStore`)로 바꿔 넣는다.
    var readingStore: any ReadingStore {
        get { self[ReadingStoreKey.self] }
        set { self[ReadingStoreKey.self] = newValue }
    }
}

// MARK: - 단어 누르기 (화면: Reader/Views → 카드: Reader/Dictionary)

/// 리더에서 단어를 눌렀을 때 넘기는 값.
nonisolated struct WordTapContext: Hashable, Sendable, Identifiable {
    var id: String { "\(bookID)#\(position.chapter).\(position.paragraph).\(position.sentence)#\(surface)" }
    /// 본문에 나온 그대로. 예: "allocated"
    var surface: String
    var bookID: String
    var language: String
    var position: ReadingPosition
    /// 단어가 들어 있는 문장 원문과 번역.
    var sentence: String
    var sentenceTranslation: String?

    /// 끌어 골라 여러 단어가 들어 있다.
    var isPhrase: Bool { surface.contains(where: \.isWhitespace) }
}
