import XCTest
@testable import VocaDay

final class ReviewHistoryStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private lazy var today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 21))!

    private func entry(
        day offset: Int,
        learningDay: Int,
        correct: Bool,
        mode: ExamItemKind = .koToEn,
        kind: SRSSessionKind = .first,
        session: UUID = UUID(),
        word: UUID = UUID()
    ) -> ReviewLogEntry {
        ReviewLogEntry(
            wordID: word, sessionID: session, learningDay: learningDay, sessionKind: kind, mode: mode,
            isCorrect: correct, stageBefore: 1, stageAfter: correct ? 2 : 0,
            answeredAt: calendar.date(byAdding: .day, value: -offset, to: today)!
        )
    }

    func testAccuracyByKindModeAndDay() {
        let first = UUID(), retry = UUID()
        let entries = [
            entry(day: 1, learningDay: 0, correct: true, mode: .match, session: first),
            entry(day: 1, learningDay: 0, correct: false, mode: .koToEn, session: first),
            entry(day: 1, learningDay: 0, correct: true, mode: .koToEn, session: first),
            entry(day: 0, learningDay: 0, correct: false, mode: .koToEn, kind: .retry, session: retry),
        ]
        let stats = ReviewHistoryStats(entries: entries, now: today, calendar: calendar)
        XCTAssertEqual(stats.firstSessionAccuracy!, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(stats.retryAccuracy, 0)
        XCTAssertEqual(stats.dailyPoints.map(\.total), [4])
        XCTAssertEqual(stats.modeAccuracies.map(\.mode), [.match, .koToEn])
        XCTAssertEqual(stats.modeAccuracies.last?.correct, 1)
        XCTAssertEqual(stats.sessions.map(\.id), [retry, first])
        XCTAssertEqual(stats.sessions.last?.total, 3)
    }

    func testCalendarStreak() {
        let entries = [0, 1, 2, 4].map { entry(day: $0, learningDay: 10 - $0, correct: true) }
        XCTAssertEqual(ReviewHistoryStats(entries: entries, now: today, calendar: calendar).calendarStreak, 3)

        let fromYesterday = [1, 2].map { entry(day: $0, learningDay: 10 - $0, correct: true) }
        XCTAssertEqual(ReviewHistoryStats(entries: fromYesterday, now: today, calendar: calendar).calendarStreak, 2)

        let broken = [2, 3].map { entry(day: $0, learningDay: 10 - $0, correct: true) }
        XCTAssertEqual(ReviewHistoryStats(entries: broken, now: today, calendar: calendar).calendarStreak, 0)
    }

    func testLearningDayRateAndEstimatedDate() {
        XCTAssertEqual(ReviewHistoryStats(entries: [], now: today, calendar: calendar).learningDaysPerCalendarDay, 1)

        // 10일 동안 학습일 5개 → 하루 0.5학습일 → 4학습일 뒤는 약 8일 뒤
        let entries = [0, 2, 4, 6, 9].enumerated().map { index, offset in entry(day: offset, learningDay: 20 - index, correct: true) }
        let stats = ReviewHistoryStats(entries: entries, now: today, calendar: calendar)
        XCTAssertEqual(stats.learningDaysPerCalendarDay, 0.5, accuracy: 0.0001)
        let expected = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: today))
        XCTAssertEqual(stats.estimatedDate(afterLearningDays: 4), expected)
    }

    func testWordHistoryNewestFirst() {
        let word = UUID()
        let entries = [entry(day: 3, learningDay: 1, correct: false, word: word), entry(day: 1, learningDay: 2, correct: true, word: word), entry(day: 1, learningDay: 2, correct: true)]
        let history = ReviewHistoryStats(entries: entries, now: today, calendar: calendar).history(for: word)
        XCTAssertEqual(history.map(\.learningDay), [2, 1])
    }
}
