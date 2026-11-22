import Foundation
import Observation
import Translation

/// 문장 여러 개를 한 번에 번역한다. 실제는 Apple Translation, 테스트는 가짜.
@MainActor
protocol SentenceTranslator {
    func translate(_ sentences: [String]) async throws -> [String]
}

/// Apple Translation(기기 안). 언어 팩이 설치돼 있어야 만들 수 있다.
@MainActor
final class AppleSentenceTranslator: SentenceTranslator {
    private let session: TranslationSession

    init(source: Locale.Language, target: Locale.Language) {
        session = TranslationSession(installedSource: source, target: target)
    }

    func translate(_ sentences: [String]) async throws -> [String] {
        let requests = sentences.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses = try await session.translations(from: requests)
        var result = Array(repeating: "", count: sentences.count)
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id), result.indices.contains(index) {
                result[index] = response.targetText
            }
        }
        return result
    }
}

/// 가져온 책 문장 번역을 기기 안에서 채운다. 책 단위로 차례대로, 중간에 멈춰도 저장된 곳부터 이어서 한다.
@MainActor
@Observable
final class BookTranslationService {
    static let shared = BookTranslationService()

    enum PackStatus: Equatable {
        case unknown
        case installed
        /// 언어 팩을 받아야 한다 (`translationTask`로 받기 안내).
        case needsDownload
        case unsupported
    }

    static let targetLanguage = Locale.Language(identifier: "ko")
    /// 한 번에 번역하는 문장 수, 이만큼마다 파일에 저장한다.
    static let batchSize = 40

    private(set) var packStatus: [String: PackStatus] = [:]
    private(set) var activeBookID: String?
    private(set) var lastError: String?
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var cancelled: Set<String> = []

    private let store: ImportedBookStore
    private let makeTranslator: @MainActor (_ source: Locale.Language) -> any SentenceTranslator

    init(
        store: ImportedBookStore? = nil,
        makeTranslator: (@MainActor (_ source: Locale.Language) -> any SentenceTranslator)? = nil
    ) {
        self.store = store ?? .shared
        self.makeTranslator = makeTranslator ?? { source in
            AppleSentenceTranslator(source: source, target: BookTranslationService.targetLanguage)
        }
    }

    func isQueued(_ bookID: String) -> Bool {
        activeBookID == bookID || queue.contains(bookID)
    }

    // MARK: Language pack

    @discardableResult
    func checkPack(source: String) async -> PackStatus {
        let status: PackStatus
        if Locale.Language(identifier: source).languageCode == Self.targetLanguage.languageCode {
            status = .unsupported // 한국어 책은 번역하지 않는다.
        } else {
            switch await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Self.targetLanguage) {
            case .installed: status = .installed
            case .supported: status = .needsDownload
            case .unsupported: status = .unsupported
            @unknown default: status = .unsupported
            }
        }
        packStatus[source] = status
        return status
    }

    // MARK: Queue

    /// 번역이 덜 된 가져온 책을 모두 이어서 번역한다. 앱을 열 때나 책 목록이 보일 때 부른다.
    func resumePending() {
        for summary in store.books.reversed() where !summary.isFullyTranslated {
            enqueue(bookID: summary.id)
        }
    }

    func enqueue(bookID: String) {
        cancelled.remove(bookID)
        guard !isQueued(bookID) else { return }
        queue.append(bookID)
        startIfNeeded()
    }

    func cancel(bookID: String) {
        queue.removeAll { $0 == bookID }
        if activeBookID == bookID { cancelled.insert(bookID) }
    }

    #if DEBUG
    func setPackStatusForTesting(_ language: String, _ status: PackStatus) {
        packStatus[language] = status
    }
    #endif

    /// 진행 중인 번역이 끝날 때까지 기다린다 (테스트용).
    func waitUntilIdle() async {
        await worker?.value
    }

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while !queue.isEmpty {
            let bookID = queue.removeFirst()
            activeBookID = bookID
            await translate(bookID: bookID)
            activeBookID = nil
        }
        worker = nil
    }

    private func translate(bookID: String) async {
        guard var book = store.book(id: bookID) else { return }
        let status = packStatus[book.language] == .installed ? .installed : await checkPack(source: book.language)
        guard status == .installed else { return } // 언어 팩이 생기면 화면이 다시 부른다.

        let translator = makeTranslator(Locale.Language(identifier: book.language))
        let pending = Self.pendingPositions(in: book)
        var start = 0
        while start < pending.count {
            if cancelled.contains(bookID) || Task.isCancelled || !store.contains(id: bookID) {
                cancelled.remove(bookID)
                return
            }
            let batch = Array(pending[start..<min(start + Self.batchSize, pending.count)])
            let sources = batch.compactMap { book.sentence(at: $0)?.text }
            do {
                let translations = try await translator.translate(sources)
                book = Self.applying(Dictionary(uniqueKeysWithValues: zip(batch, translations)), to: book)
                try await store.updateTranslations(book)
                lastError = nil
            } catch {
                // 앱이 백그라운드로 가거나 언어 팩이 지워지면 실패한다. 저장한 곳까지 남기고 다음에 이어서 한다.
                lastError = error.localizedDescription
                packStatus[book.language] = .unknown
                return
            }
            start += Self.batchSize
        }
    }

    // MARK: Pure helpers
    // 계약 1의 `positions`·`sentence(at:)`가 main actor 이므로 여기도 main actor 에서 돈다.

    /// 번역이 비어 있는 문장 위치.
    static func pendingPositions(in book: BookDocument) -> [ReadingPosition] {
        book.positions.filter { (book.sentence(at: $0)?.translation ?? "").isEmpty }
    }

    static func applying(_ translations: [ReadingPosition: String], to book: BookDocument) -> BookDocument {
        var book = book
        for (position, translation) in translations {
            let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, book.sentence(at: position) != nil else { continue }
            book.chapters[position.chapter].paragraphs[position.paragraph].sentences[position.sentence].translation = text
        }
        return book
    }

    /// 같은 책을 다시 가져왔을 때 이전 번역을 문장 글이 같은 곳에 옮긴다.
    static func mergingTranslations(from old: BookDocument, into new: BookDocument) -> BookDocument {
        var known: [String: String] = [:]
        for position in old.positions {
            if let sentence = old.sentence(at: position), let translation = sentence.translation, !translation.isEmpty {
                known[sentence.text] = translation
            }
        }
        guard !known.isEmpty else { return new }
        var updates: [ReadingPosition: String] = [:]
        for position in pendingPositions(in: new) {
            if let text = new.sentence(at: position)?.text, let translation = known[text] {
                updates[position] = translation
            }
        }
        return applying(updates, to: new)
    }
}
