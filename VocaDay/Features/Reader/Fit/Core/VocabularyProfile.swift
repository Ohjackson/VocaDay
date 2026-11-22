import Foundation

/// 내 단어장 한 단어. 앱 모델과 무관한 값 (어댑터가 `VocaWord` 에서 만든다).
nonisolated struct WordbookEntry: Hashable, Sendable {
    var word: String
    /// SRS 단계 (`SRSEngine`: 0...10).
    var stage: Int
}

/// "이 사용자가 아는 단어" 추정. 분석 코어는 이 값만 본다.
nonisolated struct VocabularyProfile: Hashable, Sendable {
    nonisolated struct Settings: Hashable, Sendable, Codable {
        /// 고빈도 목록(NGSL) 상위 몇 개를 아는 단어로 볼지. 보충 목록(요일·달·수 단어)은 늘 아는 단어다.
        var generalKnownCount: Int = 2000
        /// 단어장 단어가 이 SRS 단계 이상이면 아는 단어. 앱의 「익숙함」(5~7, `DayCardView.learnedStage`)과 같다.
        /// 5단계면 간격이 4일 이상이 될 때까지 연속으로 맞힌 상태다 (`SRSEngine.baseGaps`).
        var knownStage: Int = 5

        static let standard = Settings()
    }

    /// 나중에 읽는 중 기록(단어 누른 횟수 등)으로 보정할 자리. 지금은 비어 있다.
    nonisolated struct Adjustments: Hashable, Sendable, Codable {
        /// 아는 것으로 볼 단어 (예: 여러 번 읽고도 누르지 않은 단어).
        var assumeKnown: Set<String> = []
        /// 모르는 것으로 볼 단어 (예: 읽다가 여러 번 누른 단어).
        var assumeUnknown: Set<String> = []

        static let none = Adjustments()
        var isEmpty: Bool { assumeKnown.isEmpty && assumeUnknown.isEmpty }
    }

    /// 아는 단어 표제어 (고빈도 상위 N + 단어장 높은 단계 + 보정).
    private(set) var known: Set<String>
    /// 외우는 중인 단어장 단어. 책에 다시 나오면 "복습 단어 재등장"으로 센다. 아는 단어로 세지 않는다.
    private(set) var learning: Set<String>
    var settings: Settings
    var adjustments: Adjustments
    /// 단어장 단어 수 (구 표제어 제외).
    private(set) var wordbookCount: Int
    /// 단어 목록·단어장·설정이 바뀌면 바뀐다. 캐시 열쇠.
    private(set) var version: String

    /// 테스트·미리보기용: 집합을 직접 준다.
    init(known: Set<String>, learning: Set<String> = [], settings: Settings = .standard, adjustments: Adjustments = .none) {
        self.settings = settings
        self.adjustments = adjustments
        self.known = known
        self.learning = learning
        self.wordbookCount = learning.count
        self.version = ""
        apply(adjustments)
        self.version = Self.makeVersion(known: self.known, learning: self.learning, settings: settings, extra: "direct")
    }

    /// 고빈도 목록 + 내 단어장으로 만든다.
    init(
        wordbook: [WordbookEntry],
        references: FitReferenceLists,
        lemmatizer: any Lemmatizer,
        settings: Settings = .standard,
        adjustments: Adjustments = .none
    ) {
        var known = references.general.top(settings.generalKnownCount).union(references.supplement.headwords)
        var learning = Set<String>()
        var count = 0

        // 같은 단어가 여러 데이에 있으면 가장 높은 단계를 쓴다.
        var stages: [String: Int] = [:]
        for entry in wordbook {
            let word = lemmatizer.normalize(entry.word)
            guard !word.isEmpty, !word.contains(" ") else { continue }
            stages[word] = max(stages[word] ?? Int.min, entry.stage)
        }
        for (word, stage) in stages {
            count += 1
            // 단어장 표제어가 변화형이면 목록 표제어도 함께 둔다 (예: "allocated" → "allocate").
            let heads = Set([word] + references.listedHeadwords(for: word))
            if stage >= settings.knownStage {
                known.formUnion(heads)
                learning.subtract(heads)
            } else {
                // 단어장이 고빈도 목록보다 우선한다: 외우는 중이면 아는 단어로 세지 않는다.
                known.subtract(heads)
                learning.formUnion(heads)
            }
        }

        self.settings = settings
        self.adjustments = adjustments
        self.known = known
        self.learning = learning
        self.wordbookCount = count
        self.version = ""
        apply(adjustments)
        self.version = Self.makeVersion(known: self.known, learning: self.learning, settings: settings, extra: references.fingerprint)
    }

    private mutating func apply(_ adjustments: Adjustments) {
        known.formUnion(adjustments.assumeKnown)
        learning.subtract(adjustments.assumeKnown)
        known.subtract(adjustments.assumeUnknown)
    }

    private static func makeVersion(known: Set<String>, learning: Set<String>, settings: Settings, extra: String) -> String {
        StableHash.of(["k"] + known.sorted() + ["l"] + learning.sorted() + ["\(settings.generalKnownCount)", "\(settings.knownStage)", extra])
    }

    func isKnown(_ headword: String) -> Bool { known.contains(headword) }
    func isLearning(_ headword: String) -> Bool { learning.contains(headword) }
}
