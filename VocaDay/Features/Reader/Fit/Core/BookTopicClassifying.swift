import Foundation

/// 장마다 시험 상황 여부와 글 형식을 나누는 분류기. 기기 안 모델이 없으면 `isAvailable == false`.
nonisolated protocol BookTopicClassifying: Sendable {
    var identifier: String { get }
    var isAvailable: Bool { get }
    func classify(chapterTitle: String, text: String) async throws -> ChapterTopic
}

nonisolated extension BookTopicClassifying {
    /// 장을 하나씩 분류한다. 쓸 수 없으면 nil. 일부 장이 실패하면 그 장만 nil.
    func summarize(_ book: BookDocument, chapterTokenCounts: [Int]) async -> BookTopicSummary? {
        guard isAvailable, !book.chapters.isEmpty else { return nil }
        var topics: [ChapterTopic?] = []
        for chapter in book.chapters {
            if Task.isCancelled { return nil }
            let text = chapter.paragraphs.map { $0.sentences.map(\.text).joined(separator: " ") }.joined(separator: "\n")
            topics.append(try? await classify(chapterTitle: chapter.title, text: text))
        }
        guard topics.contains(where: { $0 != nil }) else { return nil }

        var examTokens = 0
        var classifiedTokens = 0
        for (index, topic) in topics.enumerated() {
            guard let topic else { continue }
            let weight = max(chapterTokenCounts.indices.contains(index) ? chapterTokenCounts[index] : 1, 1)
            classifiedTokens += weight
            if topic.isExamSituation { examTokens += weight }
        }
        let share = classifiedTokens == 0 ? 0 : Double(examTokens) / Double(classifiedTokens)
        return BookTopicSummary(chapters: topics, examSituationShare: share, classifierIdentifier: identifier)
    }
}
