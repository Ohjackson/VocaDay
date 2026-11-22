import Foundation
import Observation
import UniformTypeIdentifiers

/// PDF 파일 → 책 저장 → 번역 시작. 가져오기 화면의 상태를 들고 있다.
@MainActor
@Observable
final class BookImporter {
    enum Phase: Equatable {
        case idle
        case working(ImportProgress)
        case finished(ImportedBookSummary, alreadyImported: Bool)
        case failed(String)
    }

    static let allowedContentTypes: [UTType] = [.pdf]

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
        guard Self.isPDF(url) else {
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
            let book = try await Self.makeBook(pdfAt: url, progress: report)
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

    /// 메인 밖에서 PDF를 읽고(필요하면 OCR) 문장으로 나눈다.
    @concurrent
    static func makeBook(pdfAt url: URL, progress: @escaping @Sendable (ImportProgress) -> Void) async throws -> BookDocument {
        let draft = try await PDFBookParser.parse(url: url, progress: progress)
        progress(ImportProgress(fraction: 1, message: "문장 나누는 중"))
        return try ImportedBookBuilder.makeBook(from: draft)
    }
}
