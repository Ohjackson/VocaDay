import Foundation
import Translation

/// 책 사전·기본 단어장에 없는 단어를 기기 안 번역(Apple Translation, 영→한)으로 한국어 뜻을 채운다.
/// 시스템 사전은 기본이 영영사전이고 특정 사전을 고르는 공개 API가 없어서, 한국어 뜻은 이 단계가 맡는다.
/// 번역 언어 팩이 없으면 건너뛴다 (리스닝 › 톱니바퀴에서 받는다).
struct TranslationWordLookupStep: WordLookupStep {
    static let source = Locale.Language(identifier: "en")
    static let target = Locale.Language(identifier: "ko")

    /// 번역 언어 팩이 기기에 있는지. 테스트에서 바꿔 끼운다.
    var isAvailable: () async -> Bool = Self.isPackInstalled
    /// 낱말 → 한국어. 테스트에서 바꿔 끼운다. 쓸 수 없으면 nil.
    var translate: (String) async -> String? = Self.translateOnDevice

    static let packMissingMessage = "번역 언어 팩을 받으면 한국어 뜻이 나와요. 리스닝 › 톱니바퀴에서 받을 수 있어요."

    func lookup(_ request: WordLookupRequest) async throws -> WordLookupResult? {
        guard await isAvailable() else {
            // 다음 단계(Mac 시스템 사전)는 계속 돈다. 끝까지 못 찾으면 이 안내가 카드에 보인다.
            throw WordLookupStepFailure(miss: WordLookupMiss(message: Self.packMissingMessage))
        }
        // 원형이 있으면 원형으로 (arrived → arrive → "도착하다"), 없으면 본문 모양으로.
        let headword = request.lemma ?? request.surface
        for term in [headword, request.surface].reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
            guard let meaning = await translate(term), Self.isMeaningful(meaning, for: term) else { continue }
            return WordLookupResult(
                headword: term,
                surface: request.surface,
                partOfSpeech: EnglishPartOfSpeech.abbreviation(of: request.surface, in: request.sentence, meaning: meaning),
                meaning: meaning,
                note: nil,
                toeicTag: nil,
                source: .translation
            )
        }
        return nil
    }

    /// 번역이 영어 그대로 돌아오면(이름·모르는 말) 뜻으로 보지 않는다.
    static func isMeaningful(_ meaning: String, for term: String) -> Bool {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty, trimmed.lowercased() != term.lowercased() else { return false }
        return trimmed.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    private static var session: TranslationSession?
    /// 한 번 받음으로 확인되면 다시 묻지 않는다 (확인 자체가 매번 시간이 걸린다).
    private static var packInstalled = false

    static func isPackInstalled() async -> Bool {
        if packInstalled { return true }
        packInstalled = await LanguageAvailability().status(from: source, to: target) == .installed
        return packInstalled
    }

    /// 언어 팩이 있으면 세션을 만들고 한 번 번역해 둔다. 첫 단어 번역이 늦지 않게 하려는 것이다.
    static func warmUp() async {
        guard await isPackInstalled() else { return }
        _ = await translateOnDevice("hello")
    }

    static func translateOnDevice(_ term: String) async -> String? {
        let session = session ?? TranslationSession(installedSource: source, target: target)
        Self.session = session
        return try? await session.translate(term).targetText
    }
}
