import Foundation

/// 문제 유형 (SPEC §3.2, §4).
nonisolated enum ExamItemKind: String, Codable, Sendable {
    /// 새 단어 카드. 채점하지 않는다.
    case newWord = "NEW"
    /// M1 짝 맞추기
    case match = "M1"
    /// M2 예문 빈칸 고르기
    case choice = "M2"
    /// M3 예문 빈칸 쓰기
    case clozeTyping = "M3"
    /// M4 한국어 → 영어 쓰기 (stage ≥ 2, 단계에 따라 첫 글자·글자 수 힌트)
    case koToEn = "M4"
    /// M5 영어 → 한국어 뜻 고르기 (5지선다)
    case meaningChoice = "M5"
    /// M6 예문 빈칸 고르기 — 한국어 번역 없이 영어 문맥만으로 (5지선다)
    case clozeChoiceWithoutTranslation = "M6"
    /// M7 글자 조각 맞추기 — 뜻을 보고 섞인 알파벳 조각으로 단어를 완성 (떠올리기, 철자 부담 낮음)
    case letterTiles = "M7"
    /// M8 듣고 쓰기 — 발음만 듣고 철자를 입력 (떠올리기)
    case dictation = "M8"
    /// 복습 탭의 카드 자기 평가 (알아요/다시). 계획에는 들어가지 않고 풀이 로그에만 쓴다.
    case flashcard = "CARD"
}

nonisolated enum ClozeHint: String, Codable, Sendable {
    /// stage 3–4: 첫 글자 + 밑줄
    case firstLetters
    /// stage 5: 글자 수만
    case length
    /// stage 6+ 대체 유형: 힌트 없음
    case none
}

nonisolated struct ExamPlanItem: Codable, Equatable, Sendable {
    var kind: ExamItemKind
    /// 채점 대상 단어. newWord는 소개할 단어 1개(채점 X).
    var wordIDs: [UUID]
    /// M1 채움 단어 (채점 X).
    var fillerWordIDs: [UUID] = []
    /// M2·M5 보기 (정답 포함, 표시 순서). M7은 글자 조각 (정답 글자 + 가짜 글자, 섞인 순서).
    var options: [String] = []
    /// M3·M4 힌트.
    var hint: ClozeHint? = nil

    var gradedWordIDs: [UUID] {
        kind == .newWord ? [] : wordIDs
    }
}

nonisolated struct ExamPlan: Codable, Equatable, Sendable {
    var items: [ExamPlanItem]
    /// 이 인덱스의 문제를 마친 뒤 "계속하기 / 나중에" 화면을 보여 준다.
    var lessonBreaksAfter: [Int]

    var gradedCount: Int {
        items.reduce(0) { $0 + $1.gradedWordIDs.count }
    }

    var gradedWordIDs: [UUID] {
        items.flatMap(\.gradedWordIDs)
    }

    static let empty = ExamPlan(items: [], lessonBreaksAfter: [])
}

/// 중간 종료 후 이어하기용 스냅샷 (SPEC §3.5). 기기 로컬에 저장한다.
nonisolated struct ActiveExamSession: Codable, Equatable, Sendable {
    var sessionID: UUID
    var kind: SRSSessionKind
    var learningDay: Int
    var plan: ExamPlan
    /// 다음에 풀 문제 인덱스.
    var cursor: Int
    /// 단어 UUID → 채점 결과 (첫 채점 결과만).
    var results: [String: Bool]
    /// 채점된 순서.
    var resultOrder: [String]
    /// 단어 UUID → "typo" / "nearMiss" (통계용, 없을 수 있음).
    var details: [String: String]?
    /// 문제 중에 예문 해석을 연 단어. 세션 끝에 한 번 더 낸다 (예전 저장본에는 없을 수 있음).
    var hintedWordIDs: [String]?

    init(sessionID: UUID = UUID(), kind: SRSSessionKind, learningDay: Int, plan: ExamPlan) {
        self.sessionID = sessionID
        self.kind = kind
        self.learningDay = learningDay
        self.plan = plan
        cursor = 0
        results = [:]
        resultOrder = []
        details = [:]
    }

    mutating func record(wordID: UUID, isCorrect: Bool, detail: String? = nil) {
        let key = wordID.uuidString
        guard results[key] == nil else { return }
        results[key] = isCorrect
        resultOrder.append(key)
        if let detail, !detail.isEmpty {
            details = (details ?? [:]).merging([key: detail]) { _, new in new }
        }
    }

    /// 채점 대상 단어가 나온 문제 유형.
    func mode(for wordID: UUID) -> ExamItemKind? {
        plan.items.first { $0.kind != .newWord && $0.wordIDs.contains(wordID) }?.kind
    }

    var orderedResults: [(wordID: UUID, isCorrect: Bool)] {
        resultOrder.compactMap { key in
            guard let id = UUID(uuidString: key), let value = results[key] else { return nil }
            return (id, value)
        }
    }

    var answeredGradedCount: Int { results.count }
}

/// `activeSessionJSON` 저장소. iCloud로 동기화하지 않고 기기에만 둔다 (두 기기 동시 진행 충돌 방지).
nonisolated struct ExamSessionStore: Sendable {
    static let standard = ExamSessionStore(storageKey: "examActiveSessionV1")

    let storageKey: String

    func load() -> ActiveExamSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ActiveExamSession.self, from: data)
    }

    func save(_ session: ActiveExamSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
