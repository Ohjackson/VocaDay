import Foundation
import FoundationModels

@Generable(description: "The kind of text a passage is written as.")
nonisolated enum GeneratedTextGenre: Sendable, Equatable, CaseIterable {
    case email
    case notice
    case advertisement
    case article
    case memo
    case schedule
    case conversation
    case narrative
    case other

    var genre: ChapterTopic.Genre {
        switch self {
        case .email: .email
        case .notice: .notice
        case .advertisement: .advertisement
        case .article: .article
        case .memo: .memo
        case .schedule: .schedule
        case .conversation: .conversation
        case .narrative: .narrative
        case .other: .other
        }
    }
}

@Generable(description: "How well one chapter of an English reading book matches TOEIC test situations.")
nonisolated struct GeneratedChapterTopic: Sendable, Equatable {
    @Guide(description: "True if the chapter is mostly about workplace, business, travel, shopping, or daily public-life situations that appear on the TOEIC test.")
    var isTOEICSituation: Bool

    @Guide(description: "One to three text forms that appear in the chapter, most prominent first.", .count(1...3))
    var genres: [GeneratedTextGenre]

    @Guide(description: "A short Korean phrase (under 20 characters) naming the situation, for example \"출장 일정 조율\".")
    var situationKo: String
}

/// 기기 안 Foundation Models 로 장의 주제를 나눈다. Apple Intelligence 를 쓸 수 없는 기기면 `isAvailable == false`.
nonisolated struct FoundationModelsTopicClassifier: BookTopicClassifying {
    var identifier: String { "fm-topic-1" }
    /// 모델 문맥이 짧아 장 앞부분만 넘긴다.
    var characterLimit = 2400

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
    You classify chapters of short English reading books for Korean TOEIC learners.
    Decide whether the chapter is set in a TOEIC-style situation (office work, meetings, hiring, \
    business travel, customer service, shopping, restaurants, housing, public announcements), \
    and which text forms it uses (email, notice, advertisement, article, memo, schedule, conversation, narrative).
    """

    func classify(chapterTitle: String, text: String) async throws -> ChapterTopic {
        let session = LanguageModelSession(model: .default, instructions: Self.instructions)
        let response = try await session.respond(
            to: "Chapter title: \(chapterTitle)\n\n\(String(text.prefix(characterLimit)))",
            generating: GeneratedChapterTopic.self,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120)
        )
        let content = response.content
        var genres: [ChapterTopic.Genre] = []
        for genre in content.genres.map(\.genre) where !genres.contains(genre) { genres.append(genre) }
        return ChapterTopic(
            isExamSituation: content.isTOEICSituation,
            genres: genres.isEmpty ? [.other] : genres,
            situation: String(content.situationKo.prefix(30))
        )
    }
}
