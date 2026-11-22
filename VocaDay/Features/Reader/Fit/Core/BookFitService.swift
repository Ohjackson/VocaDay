import Foundation

/// 보고서를 백그라운드에서 계산하고 캐시한다. 언어별 부분(원형 분석, 단어 목록, 분류기)은 만들 때 넣는다.
nonisolated final class BookFitService: Sendable {
    let analyzer: BookFitAnalyzer
    let cache: BookFitCache
    let classifier: (any BookTopicClassifying)?

    init(analyzer: BookFitAnalyzer, cache: BookFitCache, classifier: (any BookTopicClassifying)?) {
        self.analyzer = analyzer
        self.cache = cache
        self.classifier = classifier
    }

    var references: FitReferenceLists { analyzer.references }

    /// 캐시에 같은 열쇠가 있으면 그것을, 없으면 새로 계산한다. 주제 분류가 캐시에 있으면 붙인다 (새로 분류하지는 않는다).
    func report(for book: BookDocument, profile: VocabularyProfile) async -> BookFitReport {
        let analyzer = analyzer
        let key = await Task.detached(priority: .utility) { analyzer.cacheKey(book: book, profile: profile) }.value
        if let cached = await cache.report(bookID: book.id, key: key) {
            return cached
        }
        var report = await Task.detached(priority: .utility) { analyzer.analyze(book, profile: profile) }.value
        if let classifier {
            report.topics = await cache.topics(bookID: book.id, key: topicKey(book: book, classifier: classifier))
        }
        await cache.store(report)
        return report
    }

    /// 주제 분류를 붙인다. 분류기가 없거나 쓸 수 없는 기기면 그대로 돌려준다.
    func addingTopics(to report: BookFitReport, book: BookDocument) async -> BookFitReport {
        guard report.topics == nil, let classifier, classifier.isAvailable else { return report }
        let key = topicKey(book: book, classifier: classifier)
        var summary = await cache.topics(bookID: book.id, key: key)
        if summary == nil {
            summary = await classifier.summarize(book, chapterTokenCounts: report.chapters.map(\.stats.tokenCount))
            if let summary { await cache.storeTopics(summary, bookID: book.id, key: key) }
        }
        guard let summary else { return report }
        var updated = report
        updated.topics = summary
        await cache.store(updated)
        return updated
    }

    /// 단어장과 무관: 책 내용 + 분류기.
    private func topicKey(book: BookDocument, classifier: any BookTopicClassifying) -> String {
        BookFitAnalyzer.fingerprint(of: book) + "|" + classifier.identifier
    }
}
