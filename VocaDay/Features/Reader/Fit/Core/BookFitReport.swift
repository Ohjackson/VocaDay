import Foundation

/// 판정. Hu & Nation (2000): 아는 단어 98% 이상이면 도움 없이 읽고, 95% 근처면 사전과 함께 읽을 수 있다.
nonisolated enum BookFitVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    /// 98% 이상: 많이 빨리 읽기.
    case extensive
    /// 95~98%: 사전·책 사전과 함께 꼼꼼히 읽기.
    case intensive
    /// 95% 미만: 아직 어렵다.
    case notYet

    var title: String {
        switch self {
        case .extensive: "다독용"
        case .intensive: "정독용"
        case .notYet: "아직"
        }
    }

    var explanation: String {
        switch self {
        case .extensive: "모르는 단어가 거의 없어 빠르게 많이 읽기 좋아요."
        case .intensive: "책 사전과 함께 꼼꼼히 읽기 좋아요."
        case .notYet: "모르는 단어가 많아요. 단어를 더 익힌 뒤 읽어 보세요."
        }
    }
}

/// 판정 기준. 설정으로 바꿀 수 있다.
nonisolated struct BookFitCriteria: Codable, Hashable, Sendable {
    var extensiveCoverage: Double = 0.98
    var intensiveCoverage: Double = 0.95

    static let standard = BookFitCriteria()

    func verdict(coverage: Double) -> BookFitVerdict {
        // 95/100 같은 경계값이 부동소수 오차로 아래로 떨어지지 않게 한다.
        let epsilon = 1e-9
        if coverage + epsilon >= extensiveCoverage { return .extensive }
        if coverage + epsilon >= intensiveCoverage { return .intensive }
        return .notYet
    }
}

/// 책 전체나 장 하나의 값.
nonisolated struct BookFitStats: Codable, Hashable, Sendable {
    /// 센 단어 수 (고유명사·숫자 제외).
    var tokenCount: Int = 0
    var knownCount: Int = 0
    var properNounCount: Int = 0
    var numberCount: Int = 0
    var sentenceCount: Int = 0
    /// 문장 하나의 평균 단어 수 (고유명사·숫자 포함).
    var averageSentenceLength: Double = 0
    /// 토익 단어 종류 수.
    var examTypeCount: Int = 0
    /// 토익 단어가 나온 횟수.
    var examTokenCount: Int = 0
    /// 외우는 중인 단어가 나온 횟수.
    var reviewTokenCount: Int = 0
    var verdict: BookFitVerdict = .notYet

    /// 아는 단어 비율 0...1. 센 단어가 없으면 0.
    var coverage: Double { tokenCount == 0 ? 0 : Double(knownCount) / Double(tokenCount) }
    var unknownCount: Int { tokenCount - knownCount }
    var unknownPerThousand: Double { tokenCount == 0 ? 0 : Double(unknownCount) * 1000 / Double(tokenCount) }
    var examPerThousand: Double { tokenCount == 0 ? 0 : Double(examTokenCount) * 1000 / Double(tokenCount) }
}

nonisolated struct ChapterFit: Codable, Hashable, Sendable, Identifiable {
    var index: Int
    var title: String
    var stats: BookFitStats
    var id: Int { index }
}

/// 단어와 나온 횟수.
nonisolated struct FitWordCount: Codable, Hashable, Sendable, Identifiable {
    var word: String
    var count: Int
    var firstPosition: ReadingPosition
    var id: String { word }
}

nonisolated struct BookQualityWarning: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case missingTranslation
        case longSentence
        case unterminatedSentence
        case garbledText
        case glossaryPositionInvalid
        case glossaryPositionNotFirst

        var title: String {
            switch self {
            case .missingTranslation: "번역 누락"
            case .longSentence: "아주 긴 문장"
            case .unterminatedSentence: "끝맺음 없는 문장"
            case .garbledText: "깨진 글자"
            case .glossaryPositionInvalid: "사전 위치 오류"
            case .glossaryPositionNotFirst: "사전 위치가 첫 등장이 아님"
            }
        }

        /// 배지 한 줄에 "문장 오류"로 묶어 보일 종류.
        var isSentenceProblem: Bool {
            switch self {
            case .longSentence, .unterminatedSentence, .garbledText: true
            default: false
            }
        }
    }

    var kind: Kind
    /// 문장 수 (깨진 글자는 깨진 글자가 있는 문장 수).
    var count: Int
    /// 앞쪽 몇 개만.
    var positions: [ReadingPosition]
    /// 예: 사전 위치 오류의 표제어, 깨진 글자 비율.
    var details: [String]
    var id: Kind { kind }
}

/// 장 하나의 주제 분류 (기기 안 모델). 쓸 수 없는 기기면 없다.
nonisolated struct ChapterTopic: Codable, Hashable, Sendable {
    nonisolated enum Genre: String, Codable, Hashable, Sendable, CaseIterable {
        case email, notice, advertisement, article, memo, schedule, conversation, narrative, other

        var title: String {
            switch self {
            case .email: "이메일"
            case .notice: "공지"
            case .advertisement: "광고"
            case .article: "기사"
            case .memo: "메모"
            case .schedule: "일정표"
            case .conversation: "대화"
            case .narrative: "이야기"
            case .other: "기타"
            }
        }
    }

    var isExamSituation: Bool
    var genres: [Genre]
    /// 한국어 짧은 상황 설명. 예: "출장 일정 조율"
    var situation: String
}

nonisolated struct BookTopicSummary: Codable, Hashable, Sendable {
    /// 장 순서. 분류에 실패한 장은 nil.
    var chapters: [ChapterTopic?]
    /// 토익 상황 장의 단어 수 비율 0...1.
    var examSituationShare: Double
    var classifierIdentifier: String
}

nonisolated struct BookFitReport: Codable, Hashable, Sendable, Identifiable {
    static let analyzerVersion = 1

    var bookID: String
    var bookTitle: String
    var language: String
    var generatedAt: Date
    var cacheKey: String
    var criteria: BookFitCriteria
    /// 예: ["NGSL 2809", "TSL 1250", "기본 단어장 2391"]
    var referenceSources: [String]
    var profileWordbookCount: Int
    var generalKnownCount: Int

    var overall: BookFitStats
    var chapters: [ChapterFit]
    /// 나온 토익 단어, 많이 나온 순.
    var examWords: [FitWordCount]
    /// 다시 나온 외우는 중 단어, 많이 나온 순.
    var reviewWords: [FitWordCount]
    /// 모르는 단어(아는 단어도 외우는 중도 아닌 것), 많이 나온 순, 앞쪽 몇 개만.
    var unknownWords: [FitWordCount]
    var quality: [BookQualityWarning]
    /// 깨진 글자 / 공백 아닌 글자.
    var garbledRatio: Double
    /// nil 이면 분류하지 않았다 (기기 안 모델 없음).
    var topics: BookTopicSummary?

    var id: String { bookID }
    var verdict: BookFitVerdict { overall.verdict }

    func warningCount(_ kind: BookQualityWarning.Kind) -> Int {
        quality.first { $0.kind == kind }?.count ?? 0
    }

    var sentenceProblemCount: Int {
        quality.filter(\.kind.isSentenceProblem).map(\.count).reduce(0, +)
    }

    var glossaryProblemCount: Int {
        warningCount(.glossaryPositionInvalid) + warningCount(.glossaryPositionNotFirst)
    }

    /// 가장 어려운 장 (아는 단어 비율이 가장 낮은 장).
    var hardestChapter: ChapterFit? {
        chapters.filter { $0.stats.tokenCount > 0 }.min { $0.stats.coverage < $1.stats.coverage }
    }
}

/// 계약 `BookDocument` 의 확장(`positions`, `sentence(at:)`)은 앱 기본 격리(MainActor)를 받는다.
/// 분석은 백그라운드에서 돌리므로 같은 일을 하는 격리 없는 도우미를 따로 둔다.
nonisolated extension BookDocument {
    /// 본문 순서대로 (위치, 문장).
    var fitSentences: [(position: ReadingPosition, sentence: BookSentence)] {
        var result: [(position: ReadingPosition, sentence: BookSentence)] = []
        for (c, chapter) in chapters.enumerated() {
            for (p, paragraph) in chapter.paragraphs.enumerated() {
                for (s, sentence) in paragraph.sentences.enumerated() {
                    result.append((ReadingPosition(chapter: c, paragraph: p, sentence: s), sentence))
                }
            }
        }
        return result
    }
}
