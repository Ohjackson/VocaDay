import Foundation

/// 보고서 캐시. 열쇠 = 책 ID + 프로필 버전 + 분석 규칙 + 책 내용 지문 (`BookFitAnalyzer.cacheKey`).
/// 책마다 가장 최근 보고서 하나만 둔다. 열쇠가 다르면(단어장이 바뀜, 책을 다시 가져옴) 없는 것으로 보고 새로 계산한다.
/// 주제 분류는 단어장과 무관하고 느리므로 책 내용 지문으로 따로 둔다.
actor BookFitCache {
    private let directory: URL?
    private var reports: [String: BookFitReport] = [:]
    private var topics: [String: BookTopicSummary] = [:]

    /// directory 가 nil 이면 메모리에만 둔다 (테스트).
    init(directory: URL?) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BookFit", isDirectory: true)
    }

    func report(bookID: String, key: String) -> BookFitReport? {
        if let report = reports[bookID] {
            return report.cacheKey == key ? report : nil
        }
        guard let url = fileURL(prefix: "report", bookID: bookID),
              let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder().decode(BookFitReport.self, from: data) else { return nil }
        reports[bookID] = report
        return report.cacheKey == key ? report : nil
    }

    func store(_ report: BookFitReport) {
        reports[report.bookID] = report
        write(report, prefix: "report", bookID: report.bookID)
    }

    func topics(bookID: String, key: String) -> BookTopicSummary? {
        let id = bookID + "|" + key
        if let summary = topics[id] { return summary }
        guard let url = fileURL(prefix: "topic-" + StableHash.of([key]), bookID: bookID),
              let data = try? Data(contentsOf: url),
              let summary = try? JSONDecoder().decode(BookTopicSummary.self, from: data) else { return nil }
        topics[id] = summary
        return summary
    }

    func storeTopics(_ summary: BookTopicSummary, bookID: String, key: String) {
        topics[bookID + "|" + key] = summary
        write(summary, prefix: "topic-" + StableHash.of([key]), bookID: bookID)
    }

    /// 책 하나의 캐시를 지운다 (책 삭제 등).
    func remove(bookID: String) {
        reports[bookID] = nil
        topics = topics.filter { !$0.key.hasPrefix(bookID + "|") }
        guard let directory else { return }
        let marker = "-" + Self.safeName(bookID) + ".json"
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasSuffix(marker) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func removeAll() {
        reports = [:]
        topics = [:]
        if let directory {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func write(_ value: some Encodable, prefix: String, bookID: String) {
        guard let url = fileURL(prefix: prefix, bookID: bookID),
              let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(prefix: String, bookID: String) -> URL? {
        directory?.appendingPathComponent("\(prefix)-\(Self.safeName(bookID)).json")
    }

    private static func safeName(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
        let cleaned = String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned + "_" + StableHash.of([id])
    }
}
