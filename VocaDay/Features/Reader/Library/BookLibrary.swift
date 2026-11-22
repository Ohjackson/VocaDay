import Foundation
import os

/// 앱 번들에 들어 있는 책(`Resources/Books/*.json`)을 읽는다.
///
/// Xcode의 동기화 폴더는 리소스를 하위 폴더 없이 번들 맨 위에 복사한다. 그래서 `Books` 하위 폴더를 먼저 보고,
/// 없으면 번들 맨 위의 JSON 중 앞부분에 `"formatVersion"` 이 있는 파일만 책 후보로 본다.
/// 형식 버전이 다르거나 깨진 파일은 건너뛰고 로그만 남긴다.
nonisolated enum BookLibrary {
    enum LoadError: Error, Equatable {
        case unsupportedFormat(Int)
        case empty
    }

    /// 앱 번들의 책. 처음 쓸 때 한 번만 읽는다.
    static let bundled: [BookDocument] = load(from: bookURLs(in: .main))

    static func book(id: String) -> BookDocument? {
        bundled.first { $0.id == id }
    }

    /// 파일을 읽어 책으로 만든다. 같은 `id` 가 여러 번 나오면 처음 것만 남긴다. `id` 순서로 돌려준다.
    static func load(from urls: [URL]) -> [BookDocument] {
        var books: [String: BookDocument] = [:]
        for url in urls {
            do {
                let book = try decode(Data(contentsOf: url))
                if books[book.id] != nil {
                    logger.error("같은 책 id가 또 있어 건너뜀: \(book.id, privacy: .public) (\(url.lastPathComponent, privacy: .public))")
                    continue
                }
                books[book.id] = book
            } catch {
                logger.error("책 파일을 건너뜀: \(url.lastPathComponent, privacy: .public) — \(String(describing: error), privacy: .public)")
            }
        }
        return books.values.sorted { $0.id < $1.id }
    }

    static func decode(_ data: Data) throws -> BookDocument {
        let decoder = JSONDecoder()
        let probe = try decoder.decode(FormatProbe.self, from: data)
        guard probe.formatVersion == BookDocument.currentFormatVersion else {
            throw LoadError.unsupportedFormat(probe.formatVersion)
        }
        let book = try decoder.decode(BookDocument.self, from: data)
        guard !book.positions.isEmpty else { throw LoadError.empty }
        return book
    }

    static func bookURLs(in bundle: Bundle) -> [URL] {
        let nested = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Books") ?? []
        let flat = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []).filter(looksLikeBook)
        var seen = Set<String>()
        return (nested + flat).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// 큰 JSON(기본 단어장 등)을 통째로 읽지 않으려고 앞부분만 본다.
    static func looksLikeBook(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512) else { return false }
        return String(decoding: head, as: UTF8.self).contains("\"formatVersion\"")
    }

    private struct FormatProbe: Decodable {
        var formatVersion: Int
    }

    private static let logger = Logger(subsystem: "VocaDay", category: "BookLibrary")
}
