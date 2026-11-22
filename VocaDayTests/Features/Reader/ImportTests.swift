import CoreGraphics
import CoreText
import XCTest
@testable import VocaDay

final class ImportTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appending(path: "ImportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: Sentences & headings

    func testSentenceSplitKeepsDialogueTagsAndAbbreviations() {
        XCTAssertEqual(ImportedBookBuilder.splitSentences("“Who?” she asked. It was late.", language: "en"), ["“Who?” she asked.", "It was late."])
        XCTAssertEqual(ImportedBookBuilder.splitSentences("“Seven!” I answered.", language: "en"), ["“Seven!” I answered."])
        XCTAssertEqual(ImportedBookBuilder.splitSentences("He lives in St. John’s Wood at No. 7 Baker Street. Mr. Holmes smiled.", language: "en"), [
            "He lives in St. John’s Wood at No. 7 Baker Street.", "Mr. Holmes smiled.",
        ])
        XCTAssertFalse(ChapterHeading.isAllCapsTitle("“BALLARAT.”"))
    }

    func testChapterHeadingRecognition() {
        for heading in ["Chapter 1", "CHAPTER IV. The Storm", "Chapter Twenty-One", "II.", "XIV", "Prologue", "PART TWO"] {
            XCTAssertTrue(ChapterHeading.isNumbered(heading), heading)
        }
        for line in ["Chapters of my life were long.", "Part of the plan failed.", "Book did not arrive.", "Bookkeeping 101"] {
            XCTAssertFalse(ChapterHeading.isNumbered(line), line)
        }
    }

    // MARK: PDF cleanup

    func testBrokenHyphenOnlyJoinsLetterHyphen() {
        XCTAssertTrue(PDFLayout.endsWithBrokenHyphen("a good manage-"))
        XCTAssertFalse(PDFLayout.endsWithBrokenHyphen("she said--"))
        XCTAssertFalse(PDFLayout.endsWithBrokenHyphen("from 1990-"))
        let line = { (text: String, top: CGFloat) in PDFLine(text: text, minX: 0.1, maxX: 0.9, top: top, bottom: top + 0.03) }
        let paragraphs = PDFLayout.paragraphs(pages: [[line("a well-", 0.1), line("Known name was a manage-", 0.14), line("ment matter.", 0.18)]])
        XCTAssertEqual(paragraphs.map(\.text), ["a well- Known name was a management matter."])
    }

    func testPDFLayoutRemovesRunningHeadersPageNumbersAndJoinsHyphens() {
        func page(_ number: Int, _ body: [String]) -> [PDFLine] {
            var lines = [PDFLine(text: "THE OFFICE BOOK", minX: 0.3, maxX: 0.7, top: 0.04, bottom: 0.06)]
            for (index, text) in body.enumerated() {
                let top = 0.12 + CGFloat(index) * 0.04
                lines.append(PDFLine(text: text, minX: 0.1, maxX: text.hasSuffix(".") ? 0.5 : 0.9, top: top, bottom: top + 0.03))
            }
            lines.append(PDFLine(text: "- \(number) -", minX: 0.45, maxX: 0.55, top: 0.95, bottom: 0.97))
            return lines
        }
        let pages = [
            page(1, ["The project needed better manage-", "ment from the start of the year."]),
            page(2, ["Everyone agreed to meet on Friday", "to discuss the budget."]),
            page(3, ["The meeting went well."]),
        ]
        let chapters = PDFLayout.chapters(pages: pages, bookTitle: "Office")
        let body = chapters.flatMap(\.paragraphs)
        XCTAssertEqual(body, [
            "The project needed better management from the start of the year.",
            "Everyone agreed to meet on Friday to discuss the budget.",
            "The meeting went well.",
        ])
        XCTAssertTrue(PDFLayout.isPageNumber("12"))
        XCTAssertTrue(PDFLayout.isPageNumber("- xii -"))
        XCTAssertFalse(PDFLayout.isPageNumber("12 people came."))
    }

    func testTextPDFIsReadWithPDFKit() async throws {
        let url = tempDirectory.appending(path: "text.pdf")
        try makeTextPDF(at: url, pages: [
            ["OFFICE STORIES", "", "Chapter 1", "", "The quarterly report shows that sales rose", "by twelve percent in the last year. The man-", "agement team was pleased.", "", "1"],
            ["OFFICE STORIES", "", "Everyone agreed to meet on Friday to talk", "about the budget.", "", "2"],
        ])
        let draft = try await PDFBookParser.parse(url: url)
        XCTAssertEqual(draft.chapters.map(\.title), ["Chapter 1"])
        XCTAssertEqual(draft.chapters[0].paragraphs, [
            "The quarterly report shows that sales rose by twelve percent in the last year. The management team was pleased.",
            "Everyone agreed to meet on Friday to talk about the budget.",
        ])
    }

    func testScannedPDFIsReadWithOCR() async throws {
        let url = tempDirectory.appending(path: "scan.pdf")
        try makeImageOnlyPDF(at: url, pages: [
            ["CHAPTER ONE", "", "The quarterly report shows that", "sales increased by twelve percent."],
            ["Management plans to expand the", "marketing budget next year."],
        ])
        let draft = try await PDFBookParser.parse(url: url)
        let body = draft.chapters.flatMap(\.paragraphs).joined(separator: " ").lowercased()
        XCTAssertTrue(body.contains("quarterly report"), body)
        XCTAssertTrue(body.contains("marketing budget"), body)
        XCTAssertEqual(draft.chapters.first?.title.uppercased(), "CHAPTER ONE")
    }

    // MARK: ID

    func testSameBodyGivesSameID() throws {
        let first = ImportDraft(title: "From file name", author: nil, declaredLanguage: "en", chapters: [
            ImportDraftChapter(title: "One", paragraphs: ["Mina  arrived early.\nShe smiled.", "Done."]),
        ])
        var second = first
        second.title = "Another title"
        second.chapters[0].title = "Chapter 1"
        second.chapters[0].paragraphs[0] = "Mina arrived early. She smiled."
        let a = try ImportedBookBuilder.makeBook(from: first)
        let b = try ImportedBookBuilder.makeBook(from: second)
        XCTAssertEqual(a.id, b.id)
        XCTAssertTrue(a.id.hasPrefix("import-"))
        XCTAssertEqual(a.id.count, "import-".count + 16)

        var third = first
        third.chapters[0].paragraphs[1] = "Not done."
        XCTAssertNotEqual(try ImportedBookBuilder.makeBook(from: third).id, a.id)
    }

    func testEmptyTextThrows() {
        let empty = ImportDraft(title: "x", author: nil, declaredLanguage: nil, chapters: [ImportDraftChapter(title: "", paragraphs: ["  ", "\n"])])
        XCTAssertThrowsError(try ImportedBookBuilder.makeBook(from: empty)) {
            XCTAssertEqual($0 as? BookImportError, .noText)
        }
    }

    // MARK: Store & translation

    @MainActor
    func testStoreSavesListsAndDeletes() async throws {
        let store = ImportedBookStore(directory: tempDirectory)
        let book = try makeBook(["Hello there. How are you?"])
        try await store.add(book)
        XCTAssertEqual(store.books.map(\.id), [book.id])
        XCTAssertEqual(store.books.first?.sentenceCount, 2)
        XCTAssertEqual(store.book(id: book.id), book)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appending(path: "\(book.id).json").path))

        let reopened = ImportedBookStore(directory: tempDirectory)
        XCTAssertEqual(reopened.books.map(\.id), [book.id])
        XCTAssertEqual(reopened.books.first?.sentenceCount, 2)

        try reopened.delete(id: book.id)
        XCTAssertTrue(reopened.books.isEmpty)
        XCTAssertNil(reopened.book(id: book.id))
        XCTAssertTrue(ImportedBookStore(directory: tempDirectory).books.isEmpty)
    }

    @MainActor
    func testTranslationFillsAndResumes() async throws {
        let store = ImportedBookStore(directory: tempDirectory)
        let paragraphs = (1...5).map { "Sentence number \($0) is here." }.joined(separator: " ")
        var book = try makeBook([paragraphs])
        // 앞의 두 문장은 이미 번역된 상태 (중간에 멈춘 책).
        book = BookTranslationService.applying([
            ReadingPosition(chapter: 0, paragraph: 0, sentence: 0): "이미 1",
            ReadingPosition(chapter: 0, paragraph: 0, sentence: 1): "이미 2",
        ], to: book)
        try await store.add(book)
        XCTAssertEqual(BookTranslationService.pendingPositions(in: book).count, 3)

        let fake = FakeTranslator()
        let service = BookTranslationService(store: store, makeTranslator: { _ in fake })
        service.setPackStatusForTesting("en", .installed)
        service.enqueue(bookID: book.id)
        await service.waitUntilIdle()

        let translated = try XCTUnwrap(store.book(id: book.id))
        XCTAssertEqual(translated.positions.compactMap { translated.sentence(at: $0)?.translation }, [
            "이미 1", "이미 2", "KO: Sentence number 3 is here.", "KO: Sentence number 4 is here.", "KO: Sentence number 5 is here.",
        ])
        XCTAssertEqual(fake.received, ["Sentence number 3 is here.", "Sentence number 4 is here.", "Sentence number 5 is here."])
        XCTAssertEqual(store.summary(id: book.id)?.isFullyTranslated, true)
    }

    @MainActor
    func testReimportKeepsExistingTranslations() throws {
        let book = try makeBook(["One two. Three four."])
        let old = BookTranslationService.applying([ReadingPosition(chapter: 0, paragraph: 0, sentence: 1): "삼 사"], to: book)
        let merged = BookTranslationService.mergingTranslations(from: old, into: book)
        XCTAssertEqual(merged.sentence(at: ReadingPosition(chapter: 0, paragraph: 0, sentence: 1))?.translation, "삼 사")
        XCTAssertNil(merged.sentence(at: .start)?.translation)
    }

    // MARK: Fixtures

    private func makeBook(_ paragraphs: [String]) throws -> BookDocument {
        try ImportedBookBuilder.makeBook(from: ImportDraft(
            title: "Test", author: nil, declaredLanguage: "en",
            chapters: [ImportDraftChapter(title: "Chapter 1", paragraphs: paragraphs)]
        ))
    }

    /// 글자 층이 있는 PDF. 빈 문자열은 빈 줄.
    private func makeTextPDF(at url: URL, pages: [[String]]) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Times New Roman" as CFString, 12, nil)
        for lines in pages {
            pdf.beginPDFPage(nil)
            for (index, line) in lines.enumerated() where !line.isEmpty {
                let attributed = NSAttributedString(string: line, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                ])
                pdf.textPosition = CGPoint(x: 72, y: 720 - CGFloat(index) * 16)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), pdf)
            }
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }

    /// 글자를 이미지로 그린 페이지만 있는 PDF (글자 층 없음 = 스캔본).
    private func makeImageOnlyPDF(at url: URL, pages: [[String]]) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &mediaBox, nil))
        for lines in pages {
            let scale: CGFloat = 3
            let width = Int(mediaBox.width * scale), height = Int(mediaBox.height * scale)
            let bitmap = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let font = CTFontCreateWithName("Times New Roman" as CFString, 22 * scale, nil)
            for (index, line) in lines.enumerated() where !line.isEmpty {
                let attributed = NSAttributedString(string: line, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
                ])
                let ctLine = CTLineCreateWithAttributedString(attributed)
                bitmap.textPosition = CGPoint(x: 72 * scale, y: CGFloat(height) - (100 + CGFloat(index) * 34) * scale)
                CTLineDraw(ctLine, bitmap)
            }
            let image = try XCTUnwrap(bitmap.makeImage())
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: mediaBox)
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }
}

@MainActor
private final class FakeTranslator: SentenceTranslator {
    var received: [String] = []
    func translate(_ sentences: [String]) async throws -> [String] {
        received += sentences
        return sentences.map { "KO: " + $0 }
    }
}

/// 실제 책 파일로 가져오기를 돌려 본다. `TEST_RUNNER_IMPORT_SAMPLES=<폴더>` 를 주고 실행할 때만 돈다 (파일은 저장소에 넣지 않는다).
/// 폴더 안 PDF 를 가져와 결과 책 JSON 을 테스트 첨부(xcresult)로 남긴다.
final class ImportSampleFileTests: XCTestCase {
    @MainActor
    func testImportSampleFilesFromEnvironment() async throws {
        guard let folder = ProcessInfo.processInfo.environment["IMPORT_SAMPLES"] else {
            throw XCTSkip("IMPORT_SAMPLES 가 없다.")
        }
        let directory = URL(filePath: folder, directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var report: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard BookImporter.isPDF(file) else { continue }
            let started = Date()
            let book = try await BookImporter.makeBook(pdfAt: file, progress: { _ in })
            let seconds = Date().timeIntervalSince(started)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let attachment = XCTAttachment(data: try encoder.encode(book), uniformTypeIdentifier: "public.json")
            attachment.name = file.lastPathComponent + ".json"
            attachment.lifetime = .keepAlways
            add(attachment)
            report.append("\(file.lastPathComponent): \(book.chapters.count) chapters, \(book.positions.count) sentences, id \(book.id), \(String(format: "%.1f", seconds))s")
        }
        let summary = XCTAttachment(string: report.joined(separator: "\n"))
        summary.name = "summary.txt"
        summary.lifetime = .keepAlways
        add(summary)
        XCTAssertFalse(report.isEmpty)
    }
}
