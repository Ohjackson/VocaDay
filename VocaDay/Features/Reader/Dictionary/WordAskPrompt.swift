import Foundation

/// 「⋯ → ChatGPT에 묻기 / Claude에 묻기 / 질문 복사」에 쓰는 질문 글.
/// 사전에 없는 숙어·문맥 뜻을 다른 AI에게 물을 수 있게 문장까지 함께 넣는다.
nonisolated struct WordAskPrompt: Hashable, Sendable {
    var surface: String
    var sentence: String
    var sentenceTranslation: String?

    init(surface: String, sentence: String, sentenceTranslation: String?) {
        self.surface = surface.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        self.sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sentenceTranslation = sentenceTranslation?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(_ context: WordTapContext) {
        self.init(surface: context.surface, sentence: context.sentence, sentenceTranslation: context.sentenceTranslation)
    }

    var text: String {
        var lines = [
            "영어 단어 뜻을 한국어로 알려줘.",
            "단어: \(surface)",
        ]
        if !sentence.isEmpty { lines.append("문장: \(sentence)") }
        if let sentenceTranslation, !sentenceTranslation.isEmpty { lines.append("문장 번역: \(sentenceTranslation)") }
        lines += [
            "",
            "1) 원형과 품사",
            "2) 이 문장에서의 뜻 (한 줄)",
            "3) 숙어·구동사의 일부면 그 표현 전체와 뜻",
            "4) 다른 주요 뜻 1~2개",
            "5) 토익에서 자주 나오는 쓰임 한 줄",
            "짧게 답해줘.",
        ]
        return lines.joined(separator: "\n")
    }

    /// 질문을 미리 채워 여는 주소.
    enum Destination: String, CaseIterable, Sendable {
        case chatGPT
        case claude

        var title: String {
            switch self {
            case .chatGPT: "ChatGPT에 묻기"
            case .claude: "Claude에 묻기"
            }
        }

        fileprivate var base: String {
            switch self {
            case .chatGPT: "https://chatgpt.com/"
            case .claude: "https://claude.ai/new"
            }
        }
    }

    func url(for destination: Destination) -> URL? {
        guard var components = URLComponents(string: destination.base) else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        // `+`·`&`가 글 안에 있어도 깨지지 않게 한 번 더 막는다.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
