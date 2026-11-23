import XCTest
@testable import VocaDay

/// 마일드 책 화면: 화면 크기 페이지 나누기. 문장은 쪼개지 않고, 장은 새 페이지에서 시작한다.
@MainActor
final class ReaderPaginatorTests: XCTestCase {
    /// iPhone 17 Pro 크기 (상태 막대 62pt, 홈 표시 34pt).
    private let phone = ReaderPageMetrics.screen(
        size: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34, fontSize: 17, lineHeight: 1.6
    )

    func testPhonePageIsTheScreenWithSafeMargins() {
        XCTAssertEqual(phone.pageWidth, 402)
        XCTAssertEqual(phone.pageHeight, 874)
        XCTAssertEqual(phone.marginX, 24)
        XCTAssertEqual(phone.bodyWidth, 354)
        XCTAssertEqual(phone.marginTop, 62 + 40, "상태 막대 아래에서 시작")
        XCTAssertEqual(phone.marginBottom, 34 + 28, "홈 표시 위에서 끝")
        XCTAssertLessThan(phone.pageNumberTop, phone.marginTop)
        XCTAssertGreaterThan(phone.pageNumberTop, 62, "쪽 번호도 상태 막대 아래")
    }

    func testMacColumnIsCenteredAtReadableWidth() {
        let layout = ReaderPagerLayout(size: CGSize(width: 1000, height: 760), minMarginX: 48, limitsBodyWidth: true)
        let mac = layout.metrics(fontSize: 17, lineHeight: 1.6)
        XCTAssertEqual(mac.bodyWidth, 594, "17pt 약 70자 = 595 → 좌우 정수 여백")
        XCTAssertEqual(mac.marginX, 203)
        XCTAssertEqual(mac.pageHeight, 760)

        // 창이 본문 열보다 좁으면 최소 여백만 둔다.
        let narrow = ReaderPagerLayout(size: CGSize(width: 560, height: 700), minMarginX: 48, limitsBodyWidth: true)
            .metrics(fontSize: 17, lineHeight: 1.6)
        XCTAssertEqual(narrow.marginX, 48)
        XCTAssertEqual(narrow.bodyWidth, 464)
    }

    func testSmallerScreenMakesMorePages() {
        let book = Self.longBook()
        let small = ReaderPageMetrics.screen(size: CGSize(width: 375, height: 667), safeTop: 20, fontSize: 17, lineHeight: 1.6)
        XCTAssertGreaterThan(
            ReaderPaginator.paginate(book: book, metrics: small).count,
            ReaderPaginator.paginate(book: book, metrics: phone).count
        )
    }

    func testEverySentenceAppearsOnceInOrder() {
        let book = Self.longBook()
        let pages = ReaderPaginator.paginate(book: book, metrics: phone)
        XCTAssertGreaterThan(pages.count, 3)
        XCTAssertEqual(pages.flatMap(\.positions), book.positions)
        XCTAssertEqual(pages.map(\.index), Array(pages.indices))
        for page in pages {
            XCTAssertEqual(page.sentenceTops.count, page.positions.count)
            XCTAssertEqual(page.sentenceTops, page.sentenceTops.sorted(), "문장 위치는 위에서 아래로")
        }
    }

    func testPagesFitBodyHeight() {
        let book = Self.longBook()
        let pages = ReaderPaginator.paginate(book: book, metrics: phone)
        let composer = ReaderPageComposer(book: book, fontSize: phone.fontSize, lineHeight: phone.lineHeight)
        for page in pages where page.positions.count > 1 {
            let stack = ReaderTextStack(width: phone.bodyWidth)
            stack.storage.setAttributedString(composer.compose(page.blocks).0)
            XCTAssertLessThanOrEqual(stack.usedHeight, phone.bodyHeight + 0.5, "페이지 \(page.index)")
        }
    }

    func testChaptersStartNewPageWithoutTitle() {
        let book = Self.longBook()
        let pages = ReaderPaginator.paginate(book: book, metrics: phone)
        for chapter in book.chapters.indices {
            let first = pages.first { $0.chapter == chapter }
            XCTAssertEqual(first?.firstPosition, ReadingPosition(chapter: chapter, paragraph: 0, sentence: 0))
            if case .paragraph? = first?.blocks.first {} else { XCTFail("장 첫 페이지는 본문으로 시작해야 한다") }
        }
    }

    func testIndentsOnlyParagraphStartsAfterTheFirst() {
        let pages = ReaderPaginator.paginate(book: Self.longBook(), metrics: phone)
        var sawContinuation = false
        for case .paragraph(_, let paragraph, let sentences, let indented) in pages.flatMap(\.blocks) {
            if sentences.lowerBound > 0 {
                sawContinuation = true
                XCTAssertFalse(indented, "앞 페이지에서 이어지는 문단은 들여쓰지 않는다")
            } else {
                XCTAssertEqual(indented, paragraph > 0, "장 첫 문단만 들여쓰지 않는다")
            }
        }
        XCTAssertTrue(sawContinuation, "긴 문단이 페이지를 넘어가는 경우를 포함해야 한다")
    }

    func testBiggerTextMakesMorePages() {
        let book = Self.longBook()
        let small = ReaderPaginator.paginate(book: book, metrics: Self.phoneSize(fontSize: 14))
        let large = ReaderPaginator.paginate(book: book, metrics: Self.phoneSize(fontSize: 22))
        XCTAssertLessThan(small.count, large.count)
        XCTAssertEqual(large.flatMap(\.positions), book.positions)
    }

    func testSampleBookFitsAndPageLookupWorks() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let pages = ReaderPaginator.paginate(book: book, metrics: phone)
        let target = try XCTUnwrap(book.positions.last)
        let page = try XCTUnwrap(pages.first { $0.positions.contains(target) })
        XCTAssertNotNil(page.top(of: target))
        XCTAssertNil(page.top(of: ReadingPosition(chapter: 99, paragraph: 0, sentence: 0)))
    }

    func testPageTextFindsTappedWord() throws {
        let book = try XCTUnwrap(BookLibrary.book(id: "sample-first-week"))
        let pages = ReaderPaginator.paginate(book: book, metrics: phone)
        let text = ReaderPageText(book: book, page: pages[0], metrics: phone, palette: ReaderTheme.oldBook.palette)
        let first = pages[0].positions[0]
        let ref = ReaderTokenRef(position: first, index: 1)
        let rect = try XCTUnwrap(text.wordRect(ref))
        let hit = try XCTUnwrap(text.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
        XCTAssertEqual(hit.position, first)
        XCTAssertEqual(hit.token, 1)
        XCTAssertFalse(text.sentenceRects(first).isEmpty)
        XCTAssertNil(text.hit(at: CGPoint(x: 2, y: 2)), "여백은 누를 곳이 아니다")
    }

    // MARK: 도우미

    static func phoneSize(fontSize: CGFloat) -> ReaderPageMetrics {
        .screen(size: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34, fontSize: fontSize, lineHeight: 1.6)
    }

    /// 장 3개, 장마다 긴 문단이 섞인 책.
    static func longBook() -> BookDocument {
        let words = ["The", "quarterly", "budget", "review", "was", "scheduled", "for", "Thursday", "morning,", "and", "every", "department", "submitted", "its", "estimates", "on", "time."]
        func sentence(_ seed: Int) -> BookSentence {
            let count = 8 + seed % 9
            let text = (0..<count).map { words[($0 + seed) % words.count] }.joined(separator: " ")
            return BookSentence(text: text.prefix(1).uppercased() + text.dropFirst() + ".", translation: "번역 \(seed)")
        }
        var seed = 0
        let chapters = (0..<3).map { chapter in
            BookChapter(title: "Chapter title \(chapter + 1)", paragraphs: (0..<5).map { paragraph in
                BookParagraph(sentences: (0..<(paragraph == 2 ? 14 : 4)).map { _ in
                    seed += 1
                    return sentence(seed)
                })
            })
        }
        return BookDocument(
            formatVersion: 1, id: "long", language: "en", title: "Long", subtitle: nil, author: nil,
            level: nil, summary: nil, chapters: chapters, glossary: []
        )
    }
}
