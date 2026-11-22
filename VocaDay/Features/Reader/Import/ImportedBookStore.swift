import Foundation
import Observation

/// 가져온 책 목록 한 줄. 책 JSON을 다 읽지 않고 목록을 그리기 위한 요약.
nonisolated struct ImportedBookSummary: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var author: String?
    var language: String
    var chapterCount: Int
    var sentenceCount: Int
    var translatedCount: Int
    var importedAt: Date

    var isFullyTranslated: Bool { translatedCount >= sentenceCount }
    var translationFraction: Double { sentenceCount == 0 ? 1 : Double(translatedCount) / Double(sentenceCount) }

    init(book: BookDocument, importedAt: Date) {
        let sentences = book.chapters.flatMap(\.paragraphs).flatMap(\.sentences)
        id = book.id
        title = book.title
        author = book.author
        language = book.language
        chapterCount = book.chapters.count
        sentenceCount = sentences.count
        translatedCount = sentences.filter { !($0.translation ?? "").isEmpty }.count
        self.importedAt = importedAt
    }
}

/// `Application Support/ImportedBooks/<id>.json` 파일 층. 어느 스레드에서나 쓸 수 있다.
nonisolated struct ImportedBookFiles: Sendable {
    let directory: URL
    static let indexFileName = "index.json"

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "ImportedBooks", directoryHint: .isDirectory)
    }

    func url(for id: String) -> URL {
        directory.appending(path: "\(Self.safeFileName(id)).json")
    }

    func load(id: String) throws -> BookDocument {
        try JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: url(for: id)))
    }

    func write(_ book: BookDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(book).write(to: url(for: book.id), options: .atomic)
    }

    func delete(id: String) throws {
        let url = url(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func readIndex() -> [ImportedBookSummary]? {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.indexFileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ImportedBookSummary].self, from: data)
    }

    func writeIndex(_ summaries: [ImportedBookSummary]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(summaries).write(to: directory.appending(path: Self.indexFileName), options: .atomic)
    }

    /// 목록 파일이 없거나 깨졌을 때 책 파일들로 다시 만든다.
    func rebuildIndex() -> [ImportedBookSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.indexFileName }
            .compactMap { file in
                guard let book = try? JSONDecoder().decode(BookDocument.self, from: Data(contentsOf: file)) else { return nil }
                let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
                return ImportedBookSummary(book: book, importedAt: created)
            }
    }

    private static func safeFileName(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" })
    }
}

/// 가져온 책 저장소. 목록(`books`)은 최근에 가져온 책이 먼저.
@MainActor
@Observable
final class ImportedBookStore {
    static let shared = ImportedBookStore()

    private(set) var books: [ImportedBookSummary] = []
    let files: ImportedBookFiles

    init(directory: URL = ImportedBookFiles.defaultDirectory) {
        files = ImportedBookFiles(directory: directory)
        refresh()
    }

    static func isImportedBookID(_ id: String) -> Bool {
        id.hasPrefix(ImportedBookBuilder.idPrefix)
    }

    func refresh() {
        let summaries: [ImportedBookSummary]
        if let index = files.readIndex() {
            summaries = index.filter { FileManager.default.fileExists(atPath: files.url(for: $0.id).path) }
        } else {
            summaries = files.rebuildIndex()
            try? files.writeIndex(summaries)
        }
        books = summaries.sorted { $0.importedAt > $1.importedAt }
    }

    func contains(id: String) -> Bool {
        books.contains { $0.id == id }
    }

    func summary(id: String) -> ImportedBookSummary? {
        books.first { $0.id == id }
    }

    /// 리더에서 책을 열 때 쓴다. 없으면 nil.
    func book(id: String) -> BookDocument? {
        try? files.load(id: id)
    }

    /// 새로 가져온 책을 저장한다. 같은 ID가 이미 있으면 번역이 더 많이 된 쪽을 남긴다.
    @discardableResult
    func add(_ book: BookDocument) async throws -> ImportedBookSummary {
        var book = book
        let files = files
        if let existing = try? await Self.load(files, id: book.id) {
            book = BookTranslationService.mergingTranslations(from: existing, into: book)
        }
        try await Self.write(files, book)
        let summary = ImportedBookSummary(book: book, importedAt: self.summary(id: book.id)?.importedAt ?? .now)
        upsert(summary)
        return summary
    }

    /// 번역이 채워진 책을 다시 쓴다. 그사이 지워진 책이면 쓰지 않는다.
    func updateTranslations(_ book: BookDocument) async throws {
        guard let old = summary(id: book.id) else { return }
        try await Self.write(files, book)
        guard contains(id: book.id) else {
            try? files.delete(id: book.id)
            return
        }
        upsert(ImportedBookSummary(book: book, importedAt: old.importedAt))
    }

    func delete(id: String) throws {
        BookTranslationService.shared.cancel(bookID: id)
        try files.delete(id: id)
        books.removeAll { $0.id == id }
        try files.writeIndex(books)
    }

    private func upsert(_ summary: ImportedBookSummary) {
        books.removeAll { $0.id == summary.id }
        books.append(summary)
        books.sort { $0.importedAt > $1.importedAt }
        try? files.writeIndex(books)
    }

    @concurrent
    private static func write(_ files: ImportedBookFiles, _ book: BookDocument) async throws {
        try files.write(book)
    }

    @concurrent
    private static func load(_ files: ImportedBookFiles, id: String) async throws -> BookDocument {
        try files.load(id: id)
    }
}
