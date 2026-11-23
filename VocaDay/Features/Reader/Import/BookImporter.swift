import Foundation
import Observation
import UniformTypeIdentifiers

/// PDF·TXT 파일 → 책 저장 → 번역 시작. 가져오기 화면의 상태를 들고 있다.
@MainActor
@Observable
final class BookImporter {
    enum Phase: Equatable {
        case idle
        case working(ImportProgress)
        case finished(ImportedBookSummary, alreadyImported: Bool)
        case failed(String)
    }

    static let allowedContentTypes: [UTType] = [.pdf, .plainText]

    private(set) var phase: Phase = .idle
    private let store: ImportedBookStore
    private let translator: BookTranslationService

    init(store: ImportedBookStore? = nil, translator: BookTranslationService? = nil) {
        self.store = store ?? .shared
        self.translator = translator ?? .shared
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func reset() {
        phase = .idle
    }

    func importFile(at url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let isPDF = Self.isPDF(url)
        guard isPDF || Self.isText(url) else {
            phase = .failed(BookImportError.unsupportedFormat.localizedDescription)
            return
        }
        phase = .working(ImportProgress(fraction: 0, message: "파일 여는 중"))
        let report: @Sendable (ImportProgress) -> Void = { progress in
            Task { @MainActor in
                guard case .working = self.phase else { return }
                self.phase = .working(progress)
            }
        }
        do {
            let book = isPDF
                ? try await Self.makeBook(pdfAt: url, progress: report)
                : try await Self.makeBook(textAt: url)
            let alreadyImported = store.contains(id: book.id)
            let summary = try await store.add(book)
            phase = .finished(summary, alreadyImported: alreadyImported)
            if !summary.isFullyTranslated {
                translator.enqueue(bookID: summary.id)
            }
        } catch let error as BookImportError {
            phase = .failed(error.localizedDescription)
        } catch {
            phase = .failed(BookImportError.unreadable(error.localizedDescription).localizedDescription)
        }
    }

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) == true
    }

    static func isText(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .plainText) == true
    }

    /// 메인 밖에서 TXT를 읽고 문장으로 나눈다.
    @concurrent
    static func makeBook(textAt url: URL) async throws -> BookDocument {
        try ImportedBookBuilder.makeBook(from: TextBookParser.parse(url: url))
    }

    /// 메인 밖에서 PDF를 읽고(필요하면 OCR) 문장으로 나눈다.
    @concurrent
    static func makeBook(pdfAt url: URL, progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> BookDocument {
        let draft = try await PDFBookParser.parse(url: url, progress: progress)
        progress(ImportProgress(fraction: 1, message: "문장 나누는 중"))
        return try ImportedBookBuilder.makeBook(from: draft)
    }
}
