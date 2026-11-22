import SwiftData
import XCTest
@testable import VocaDay

@MainActor
final class BookmarkSyncTests: XCTestCase {
    private let book = "toeic-short-001"

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ReaderBookmarkRecord.self, ReaderPositionRecord.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func makeStore(_ container: ModelContainer, flushDelay: Duration = .seconds(60)) -> SwiftDataReadingStore {
        SwiftDataReadingStore(container: container, flushDelay: flushDelay, observesSystemEvents: false)
    }

    private func pos(_ c: Int, _ p: Int, _ s: Int) -> ReadingPosition {
        ReadingPosition(chapter: c, paragraph: p, sentence: s)
    }

    private func positionRows(_ container: ModelContainer) throws -> [ReaderPositionRecord] {
        try ModelContext(container).fetch(FetchDescriptor<ReaderPositionRecord>())
    }

    // MARK: - 북마크

    func testAddRemoveAndSortBookmarks() throws {
        let store = makeStore(try makeContainer())
        let late = store.addBookmark(at: pos(2, 0, 1), bookID: book, note: "late")
        let early = store.addBookmark(at: pos(0, 3, 0), bookID: book, note: "")
        let middle = store.addBookmark(at: pos(1, 0, 4), bookID: book, note: "memo")
        store.addBookmark(at: pos(0, 0, 0), bookID: "other-book", note: "")

        XCTAssertEqual(store.bookmarks(bookID: book).map(\.id), [early.id, middle.id, late.id])
        XCTAssertEqual(store.bookmarks(bookID: book).map(\.note), ["", "memo", "late"])

        store.removeBookmark(id: middle.id)
        XCTAssertEqual(store.bookmarks(bookID: book).map(\.id), [early.id, late.id])
        XCTAssertEqual(store.bookmarks(bookID: "other-book").count, 1)
    }

    func testBookmarksPersistAcrossStores() throws {
        let container = try makeContainer()
        let first = makeStore(container)
        let mark = first.addBookmark(at: pos(1, 2, 3), bookID: book, note: "회의 장면")
        let removed = first.addBookmark(at: pos(0, 0, 1), bookID: book, note: "")
        first.removeBookmark(id: removed.id)

        let second = makeStore(container)
        XCTAssertEqual(second.bookmarks(bookID: book), [mark])
    }

    func testBookmarksWithSameIDCountOnce() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000)
        // 백업 복원·두 기기 업로드 등으로 같은 id 행이 두 개가 된 경우.
        context.insert(ReaderBookmarkRecord(id: id, bookID: book, position: pos(0, 1, 0), note: "a", createdAt: created))
        context.insert(ReaderBookmarkRecord(id: id, bookID: book, position: pos(0, 1, 0), note: "a", createdAt: created.addingTimeInterval(5)))
        try context.save()

        let store = makeStore(container)
        XCTAssertEqual(store.bookmarks(bookID: book).count, 1)
        XCTAssertEqual(store.bookmarks(bookID: book).first?.createdAt, created)

        store.removeBookmark(id: id)
        XCTAssertEqual(store.bookmarks(bookID: book), [])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ReaderBookmarkRecord>()), 0)
    }

    // MARK: - 읽은 위치

    func testLastPositionIsBatchedThenPersisted() throws {
        let container = try makeContainer()
        let store = makeStore(container)
        XCTAssertNil(store.lastPosition(bookID: book))

        store.saveLastPosition(pos(0, 0, 1), bookID: book)
        store.saveLastPosition(pos(0, 0, 2), bookID: book)
        store.saveLastPosition(pos(0, 1, 0), bookID: book)
        XCTAssertEqual(store.lastPosition(bookID: book), pos(0, 1, 0))
        XCTAssertEqual(try positionRows(container).count, 0, "문장마다 디스크에 쓰지 않는다")

        store.flush()
        let rows = try positionRows(container)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.position, pos(0, 1, 0))

        store.saveLastPosition(pos(3, 0, 0), bookID: book)
        store.flush()
        XCTAssertEqual(try positionRows(container).count, 1, "같은 책은 행 하나를 고쳐 쓴다")

        let reopened = makeStore(container)
        XCTAssertEqual(reopened.lastPosition(bookID: book), pos(3, 0, 0))
    }

    func testFlushHappensAfterDelay() async throws {
        let container = try makeContainer()
        let store = makeStore(container, flushDelay: .milliseconds(50))
        store.saveLastPosition(pos(1, 1, 1), bookID: book)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(try positionRows(container).map(\.position), [pos(1, 1, 1)])
    }

    func testDuplicatePositionsMergeToNewest() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let base = Date(timeIntervalSince1970: 10_000)
        // iPhone과 Mac이 같은 책 위치 행을 따로 만들어 CloudKit에서 두 행이 된 상태.
        context.insert(ReaderPositionRecord(bookID: book, position: pos(0, 2, 0), updatedAt: base))
        context.insert(ReaderPositionRecord(bookID: book, position: pos(1, 4, 2), updatedAt: base.addingTimeInterval(60)))
        context.insert(ReaderPositionRecord(bookID: book, position: pos(0, 9, 0), updatedAt: base.addingTimeInterval(30)))
        context.insert(ReaderPositionRecord(bookID: "other-book", position: pos(0, 0, 5), updatedAt: base))
        try context.save()

        let store = makeStore(container)
        XCTAssertEqual(store.lastPosition(bookID: book), pos(1, 4, 2))
        XCTAssertEqual(store.lastPosition(bookID: "other-book"), pos(0, 0, 5))

        let rows = try positionRows(container)
        XCTAssertEqual(rows.count, 2, "책마다 한 행만 남는다")
        XCTAssertEqual(rows.first { $0.bookID == book }?.position, pos(1, 4, 2))
    }

    func testDuplicateTieKeepsSameRowOnEveryDevice() throws {
        let date = Date(timeIntervalSince1970: 5_000)
        let a = ReaderPositionRecord(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, bookID: book, position: pos(0, 0, 1), updatedAt: date)
        let b = ReaderPositionRecord(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, bookID: book, position: pos(0, 0, 2), updatedAt: date)
        XCTAssertTrue(ReaderPositionMerge.split([a, b]).keep[book] === b)
        XCTAssertTrue(ReaderPositionMerge.split([b, a]).keep[book] === b)
    }

    func testRemoteNewerPositionWinsOverOlderPending() throws {
        let container = try makeContainer()
        var clock = Date(timeIntervalSince1970: 20_000)
        let store = SwiftDataReadingStore(container: container, flushDelay: .seconds(60), observesSystemEvents: false, now: { clock })

        store.saveLastPosition(pos(0, 1, 0), bookID: book)          // 이 기기: 20000
        let remote = ModelContext(container)                          // 다른 기기: 20010
        remote.insert(ReaderPositionRecord(bookID: book, position: pos(2, 0, 0), updatedAt: clock.addingTimeInterval(10)))
        try remote.save()

        store.reload()
        XCTAssertEqual(store.lastPosition(bookID: book), pos(2, 0, 0))
        store.flush()
        XCTAssertEqual(try positionRows(container).map(\.position), [pos(2, 0, 0)])

        clock = clock.addingTimeInterval(60)
        store.saveLastPosition(pos(2, 0, 1), bookID: book)
        store.reload()
        XCTAssertEqual(store.lastPosition(bookID: book), pos(2, 0, 1), "더 늦은 미저장 값은 유지")
        store.flush()
        XCTAssertEqual(try positionRows(container).map(\.position), [pos(2, 0, 1)])
    }

    func testReloadPicksUpRemoteBookmarks() throws {
        let container = try makeContainer()
        let store = makeStore(container)
        let remote = ModelContext(container)
        remote.insert(ReaderBookmarkRecord(bookID: book, position: pos(0, 0, 3), note: "from Mac"))
        try remote.save()
        XCTAssertEqual(store.bookmarks(bookID: book), [])

        store.reload()
        XCTAssertEqual(store.bookmarks(bookID: book).map(\.note), ["from Mac"])
    }

    func testChangesNotifyObservers() throws {
        let store = makeStore(try makeContainer())
        let changed = expectation(description: "observation")
        withObservationTracking {
            _ = store.bookmarks(bookID: book)
        } onChange: {
            changed.fulfill()
        }
        store.addBookmark(at: pos(0, 0, 0), bookID: book, note: "")
        wait(for: [changed], timeout: 1)
    }

    func testAppSchemaContainsReaderModels() {
        let names = Set(VocaDayApp().sharedModelContainer.schema.entities.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["ReaderBookmarkRecord", "ReaderPositionRecord"]))
    }
}
