import XCTest
@testable import VocaDay

/// 리더 화면: 책 불러오기, 단어 나누기, 위치 이동, 북마크·읽은 위치 저장.
@MainActor
final class ReaderScreenTests: XCTestCase {
    // MARK: 책 불러오기

    func testBundledSampleBookLoads() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"), "번들에 샘플 책이 없다")
        XCTAssertEqual(book.formatVersion, BookDocument.currentFormatVersion)
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.positions.count, 6)
        XCTAssertEqual(book.glossaryEntry(forSurface: "Allocated")?.lemma, "allocate")
    }

    func testBookFilesAreFoundWithoutReadingOtherJSON() {
        let names = BookLibrary.bookURLs(in: .main).map(\.lastPathComponent)
        XCTAssertTrue(names.contains("sample-first-week.json"), "\(names)")
        XCTAssertFalse(names.contains("BundledWords.json"))
        XCTAssertFalse(names.contains("en_word_schema.json"))
    }

    func testSkipsOtherFormatVersionAndBrokenFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let good = folder.appendingPathComponent("good.json")
        try Self.bookJSON(id: "b-good", version: 1).write(to: good)
        let duplicate = folder.appendingPathComponent("duplicate.json")
        try Self.bookJSON(id: "b-good", version: 1).write(to: duplicate)
        let future = folder.appendingPathComponent("future.json")
        try Self.bookJSON(id: "b-future", version: 2).write(to: future)
        let broken = folder.appendingPathComponent("broken.json")
        try Data(#"{"formatVersion": 1, "id": "#.utf8).write(to: broken)
        let empty = folder.appendingPathComponent("empty.json")
        try Self.bookJSON(id: "b-empty", version: 1, sentences: []).write(to: empty)

        let books = BookLibrary.load(from: [good, duplicate, future, broken, empty])
        XCTAssertEqual(books.map(\.id), ["b-good"])
        XCTAssertThrowsError(try BookLibrary.decode(Self.bookJSON(id: "x", version: 2))) { error in
            XCTAssertEqual(error as? BookLibrary.LoadError, .unsupportedFormat(2))
        }
    }

    func testLooksLikeBookChecksOnlyTheHead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"[{"english": "word"}]"#.utf8).write(to: url)
        XCTAssertFalse(BookLibrary.looksLikeBook(url))
        try Self.bookJSON(id: "b", version: 1).write(to: url)
        XCTAssertTrue(BookLibrary.looksLikeBook(url))
    }

    // MARK: 단어 나누기

    func testTokenizerSplitsWordsAndStripsPunctuation() {
        let tokens = ReaderTokenizer.tokens(in: "“Well,” Mina’s twenty-minute review — done.")
        XCTAssertEqual(tokens.map(\.display), ["“Well,”", "Mina’s", "twenty-minute", "review", "—", "done."])
        XCTAssertEqual(tokens.map(\.surface), ["Well", "Mina's", "twenty-minute", "review", nil, "done"])
        XCTAssertNil(ReaderTokenizer.tokens(in: "It costs $12.")[2].surface)
        // 글자 위치(UTF-16)는 조판 글자 위치와 맞아야 한다
        let sentence = "“Well,” Mina’s twenty-minute review — done."
        for token in tokens {
            XCTAssertEqual((sentence as NSString).substring(with: NSRange(location: token.range.lowerBound, length: token.range.count)), token.display)
        }
    }

    // MARK: 위치 이동

    func testNavigatorMovesAcrossParagraphsAndChapters() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let navigator = ReadingNavigator(book: book)
        let p = ReadingPosition.init(chapter:paragraph:sentence:)

        XCTAssertEqual(navigator.next(after: p(0, 0, 1)), p(0, 1, 0))
        XCTAssertEqual(navigator.next(after: p(0, 1, 1)), p(1, 0, 0))
        XCTAssertNil(navigator.next(after: p(1, 0, 1)))
        XCTAssertEqual(navigator.previous(before: p(1, 0, 0)), p(0, 1, 1))
        XCTAssertNil(navigator.previous(before: .start))
        XCTAssertEqual(navigator.chapterStarts, [p(0, 0, 0), p(1, 0, 0)])
        XCTAssertEqual(navigator.ordinal(of: p(1, 0, 1)), 6)
        XCTAssertEqual(navigator.progress(of: p(1, 0, 1)), 1)
        XCTAssertEqual(navigator.progress(of: .start), 0)
    }

    func testNavigatorResolvesMissingSavedPosition() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let navigator = ReadingNavigator(book: book)
        let p = ReadingPosition.init(chapter:paragraph:sentence:)

        XCTAssertEqual(navigator.resolve(nil), .start)
        XCTAssertEqual(navigator.resolve(p(0, 1, 1)), p(0, 1, 1))
        // 책이 바뀌어 없는 문장 → 그 앞의 가장 가까운 문장
        XCTAssertEqual(navigator.resolve(p(0, 1, 9)), p(0, 1, 1))
        XCTAssertEqual(navigator.resolve(p(7, 0, 0)), p(1, 0, 1))
        XCTAssertEqual(navigator.next(after: p(0, 1, 9)), p(1, 0, 0))
    }

    // MARK: 읽기 상태 (위치 저장·북마크)

    func testSessionRestoresAndSavesLastPosition() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let store = InMemoryReadingStore()
        let p = ReadingPosition.init(chapter:paragraph:sentence:)
        store.saveLastPosition(p(0, 1, 0), bookID: book.id)

        let session = ReaderSession(book: book, store: store)
        XCTAssertEqual(session.position, p(0, 1, 0))
        XCTAssertEqual(session.scrollRequest.position, p(0, 1, 0))

        session.goNext()
        XCTAssertEqual(session.position, p(0, 1, 1))
        XCTAssertEqual(store.lastPosition(bookID: book.id), p(0, 1, 1))
        XCTAssertEqual(session.scrollRequest.serial, 1)

        session.jump(to: p(1, 0, 0))
        XCTAssertEqual(store.lastPosition(bookID: book.id), p(1, 0, 0))

        // 다시 열면 그 문장으로
        XCTAssertEqual(ReaderSession(book: book, store: store).position, p(1, 0, 0))
    }

    func testTappingWordMakesContextWithoutMovingReadingPosition() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let store = InMemoryReadingStore()
        let session = ReaderSession(book: book, store: store)
        let position = ReadingPosition(chapter: 0, paragraph: 0, sentence: 1)

        session.tapWord("allocated", ref: ReaderTokenRef(position: position, index: 4))
        let context = try XCTUnwrap(session.activeWord?.context)
        XCTAssertEqual(context.surface, "allocated")
        XCTAssertEqual(context.bookID, "sample-first-week")
        XCTAssertEqual(context.language, "en")
        XCTAssertEqual(context.position, position)
        XCTAssertEqual(context.sentence, "Her manager had already allocated a desk near the window for her.")
        XCTAssertEqual(context.sentenceTranslation, "그녀의 매니저는 이미 창가 근처 책상을 그녀에게 배정해 두었다.")
        XCTAssertEqual(session.position, .start, "단어를 눌러도 읽는 문장은 그대로")
        XCTAssertEqual(session.scrollRequest.serial, 0)
        XCTAssertNil(session.speakingPosition, "재생 중이 아니면 문장 칠이 없다")
    }

    func testScrollingUpdatesPositionOnlyWhenReadingPageLeavesScreen() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        var clock = Date()
        let session = ReaderSession(book: book, store: InMemoryReadingStore(), now: { clock })
        let page1: [ReadingPosition] = [.start, ReadingPosition(chapter: 0, paragraph: 0, sentence: 1)]
        let page2: [ReadingPosition] = [ReadingPosition(chapter: 0, paragraph: 1, sentence: 0)]
        let page3: [ReadingPosition] = [ReadingPosition(chapter: 1, paragraph: 0, sentence: 0)]

        // 연 직후에는 무시 (읽던 곳으로 스크롤하는 중)
        session.noteVisiblePages([page3])
        XCTAssertEqual(session.position, .start)

        clock += 2
        session.noteVisiblePages([page1, page2])
        XCTAssertEqual(session.position, .start, "읽던 문장이 보이는 페이지에 있으면 그대로")

        session.noteVisiblePages([[], page2, page3])
        XCTAssertEqual(session.position, page2[0], "맨 위 페이지의 첫 문장")
    }

    func testTranslationStripShowsOneSentenceAtATime() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let session = ReaderSession(book: book, store: InMemoryReadingStore())
        let other = ReadingPosition(chapter: 0, paragraph: 0, sentence: 1)

        session.toggleTranslation(at: .start)
        XCTAssertTrue(session.isTranslationRevealed(at: .start))
        session.toggleTranslation(at: other)
        XCTAssertFalse(session.isTranslationRevealed(at: .start))
        XCTAssertTrue(session.isTranslationRevealed(at: other))
        session.toggleTranslation(at: other)
        XCTAssertNil(session.translationPosition)
    }

    func testBookmarksToggleThroughStore() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let store = InMemoryReadingStore()
        let session = ReaderSession(book: book, store: store)
        let later = ReadingPosition(chapter: 1, paragraph: 0, sentence: 1)

        session.toggleBookmark(at: later)
        session.toggleBookmark(at: .start)
        XCTAssertEqual(store.bookmarks(bookID: book.id).map(\.position), [.start, later])
        XCTAssertNotNil(session.bookmark(at: later))

        session.toggleBookmark(at: later)
        XCTAssertEqual(session.bookmarks.map(\.position), [.start])
    }

    // MARK: 도우미

    private static func bookJSON(id: String, version: Int, sentences: [String] = ["Hello there."]) -> Data {
        let sentenceJSON = sentences.map { #"{"text": "\#($0)"}"# }.joined(separator: ",")
        return Data("""
            {"formatVersion": \(version), "id": "\(id)", "language": "en", "title": "T",
             "chapters": [{"title": "One", "paragraphs": [{"sentences": [\(sentenceJSON)]}]}],
             "glossary": []}
            """.utf8)
    }
}
