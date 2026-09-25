import Foundation

/// 풀이 로그 집계 (UI와 분리).
nonisolated struct ReviewHistoryStats: Sendable {
    struct DailyPoint: Identifiable, Equatable, Sendable {
        var learningDay: Int
        var date: Date
        var total: Int
        var correct: Int
        var id: Int { learningDay }
        var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    }

    struct ModeAccuracy: Identifiable, Equatable, Sendable {
        var mode: ExamItemKind
        var total: Int
        var correct: Int
        var id: String { mode.rawValue }
        var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    }

    struct SessionSummary: Identifiable, Equatable, Sendable {
        var id: UUID
        var kind: SRSSessionKind
        var learningDay: Int
        var date: Date
        var total: Int
        var correct: Int
    }

    let entries: [ReviewLogEntry]
    let now: Date
    let calendar: Calendar

    init(entries: [ReviewLogEntry], now: Date = Date(), calendar: Calendar = .current) {
        self.entries = entries.sorted { $0.answeredAt < $1.answeredAt }
        self.now = now
        self.calendar = calendar
    }

    var isEmpty: Bool { entries.isEmpty }

    /// 학습일별 채점 수·정답 수 (1차+재도전 합산).
    var dailyPoints: [DailyPoint] {
        Dictionary(grouping: entries, by: \.learningDay)
            .map { day, items in
                DailyPoint(
                    learningDay: day,
                    date: items.map(\.answeredAt).min() ?? now,
                    total: items.count,
                    correct: items.filter(\.isCorrect).count
                )
            }
            .sorted { $0.learningDay < $1.learningDay }
    }

    var modeAccuracies: [ModeAccuracy] {
        [ExamItemKind.flashcard, .match, .meaningChoice, .choice, .clozeChoiceWithoutTranslation, .letterTiles, .clozeTyping, .koToEn, .dictation].compactMap { mode in
            let items = entries.filter { $0.mode == mode }
            guard !items.isEmpty else { return nil }
            return ModeAccuracy(mode: mode, total: items.count, correct: items.filter(\.isCorrect).count)
        }
    }

    /// 최근 세션이 먼저.
    var sessions: [SessionSummary] {
        Dictionary(grouping: entries, by: \.sessionID)
            .compactMap { id, items in
                guard let first = items.first else { return nil }
                return SessionSummary(
                    id: id,
                    kind: first.sessionKind,
                    learningDay: first.learningDay,
                    date: items.map(\.answeredAt).max() ?? now,
                    total: items.count,
                    correct: items.filter(\.isCorrect).count
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// 1차 세션 정답률 (예측의 p).
    var firstSessionAccuracy: Double? {
        accuracy(of: entries.filter { $0.sessionKind == .first })
    }

    /// 재도전 정답률 (예측의 q).
    var retryAccuracy: Double? {
        accuracy(of: entries.filter { $0.sessionKind == .retry })
    }

    var overallAccuracy: Double? {
        accuracy(of: entries)
    }

    /// 오늘(또는 어제)까지 이어진, 시험을 본 달력 날짜 수.
    var calendarStreak: Int {
        let studiedDays = Set(entries.map { calendar.startOfDay(for: $0.answeredAt) })
        var day = calendar.startOfDay(for: now)
        if !studiedDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), studiedDays.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while studiedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// 달력 하루에 끝내는 학습일 수 (최근 14일 평균). 기록이 없으면 1.
    /// 학습일은 세션을 끝내야 넘어가므로, 학습일 예측을 날짜로 바꿀 때 쓴다.
    var learningDaysPerCalendarDay: Double {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -13, to: today) else { return 1 }
        let recent = entries.filter { $0.answeredAt >= windowStart }
        guard let firstDate = recent.map(\.answeredAt).min() else { return 1 }
        let learningDays = Set(recent.map(\.learningDay)).count
        let span = (calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: today).day ?? 0) + 1
        guard span >= 3 else { return 1 }
        return min(max(Double(learningDays) / Double(span), 0.2), 3)
    }

    /// 학습일 offset 뒤의 예상 날짜.
    func estimatedDate(afterLearningDays offset: Int) -> Date {
        let days = (Double(offset) / learningDaysPerCalendarDay).rounded()
        return calendar.date(byAdding: .day, value: Int(days), to: calendar.startOfDay(for: now)) ?? now
    }

    /// 단어 한 개의 풀이 이력 (최근 먼저).
    func history(for wordID: UUID) -> [ReviewLogEntry] {
        entries.filter { $0.wordID == wordID }.reversed()
    }

    private func accuracy(of items: [ReviewLogEntry]) -> Double? {
        guard !items.isEmpty else { return nil }
        return Double(items.filter(\.isCorrect).count) / Double(items.count)
    }
}
