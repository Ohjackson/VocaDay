import Foundation
import FoundationModels

@Generable(description: "The Korean meaning of an English phrase as it is used in one sentence.")
struct GeneratedPhraseMeaning: Sendable, Equatable {
    @Guide(description: "반드시 한글. 이 문장 속에서 이 구절이 뜻하는 자연스러운 한국어 뜻만 짧게. 숙어면 숙어 뜻. 문장 전체를 번역하지 않는다.")
    var meaning: String

    @Guide(description: "반드시 한글. 숙어나 자주 쓰는 형태면 짧은 설명 한 줄, 아니면 빈 문자열.")
    var note: String
}

/// 끌어 고른 구절의 뜻을 Apple Intelligence(기기 안 모델)로 만든다. 문장을 함께 줘서 그 문장 속 뜻(숙어 뜻)을 고른다.
/// 번역 언어 팩이 없거나 번역이 비었을 때 쓰인다. 모델을 쓸 수 없으면 건너뛴다.
struct PhraseMeaningLookupStep: WordLookupStep {
    var isEnabled: () -> Bool = { EnglishWordLookup.GenerationSettings.isEnabled }

    var progressMessage: String? { "구절 뜻을 만드는 중…" }

    private static let instructions = """
    당신은 한국인 영어 학습자를 위한 사전 도우미입니다.
    주어진 영어 문장 안에서 표시한 구절이 무슨 뜻인지 한국어로 짧게 알려 줍니다.
    문장 전체가 아니라 그 구절의 뜻만 씁니다. 숙어라면 글자 그대로가 아니라 숙어 뜻을 씁니다.
    """

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        let model = SystemLanguageModel.default
        guard isEnabled(), case .available = model.availability else { return nil }
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        let prompt = "문장: \(request.sentence)\n구절: \(request.surface)"
        guard let response = try? await session.respond(
            to: prompt,
            generating: GeneratedPhraseMeaning.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 160)
        ) else { return nil }
        let meaning = response.content.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard meaning.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) else { return nil }
        let note = response.content.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return WordLookupResult(
            headword: request.surface,
            surface: request.surface,
            partOfSpeech: nil,
            meaning: meaning,
            note: note.isEmpty ? nil : note,
            toeicTag: nil,
            source: .generated
        )
    }
}
