import Foundation
import SwiftData

enum BundledWordPackError: LocalizedError {
    case resourceNotFound
    case exhausted
    case alreadyAddedToday

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "번들에 포함된 기본 단어 파일을 찾을 수 없습니다."
        case .exhausted:
            "기본 단어장의 단어를 모두 추가했어요."
        case .alreadyAddedToday:
            "오늘의 단어장은 이미 만들었어요. 내일 다시 추가할 수 있어요."
        }
    }
}

/// 앱에 내장된 TOEIC 단어장(BundledWords.json). 파일 순서는 scripts/build_bundled_words.py 가 고정 시드로 섞은 순서다.
/// 진행 위치를 따로 저장하지 않고, 이미 어느 데이에 있거나 보관함(`SetAsideWord`)에 있는 단어를 건너뛰어 다음 단어를 고른다.
/// 그래서 기기 간 동기화와 데이 삭제에도 따로 맞출 상태가 없다. 하루 1데이 제한은 `VocabularyDay.source` 와 생성일로 판단한다.
enum BundledWordPack {
    static let dailyCount = 20
    static let daySource = "bundledTOEIC"

    static func loadWords(bundle: Bundle = .main) throws -> [VocaWordJSON] {
        guard let url = bundle.url(forResource: "BundledWords", withExtension: "json") else {
            throw BundledWordPackError.resourceNotFound
        }
        return try JSONWordParser.decode(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    /// 데이에도 보관함에도 없는 단어를 파일 순서대로.
    static func candidates(from pack: [VocaWordJSON], existingDays: [VocabularyDay], setAside: [SetAsideWord] = []) -> [VocaWordJSON] {
        let used = Set(existingDays.flatMap(\.wordList).map { $0.english.normalizedEnglish })
            .union(setAside.map { $0.english.normalizedEnglish })
        return pack.filter { !used.contains($0.english.normalizedEnglish) }
    }

    static func hasAddedToday(existingDays: [VocabularyDay], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        existingDays.contains { $0.source == daySource && calendar.isDate($0.createdAt, inSameDayAs: now) }
    }

    /// 검수 결과로 새 데이를 만들고, 뺀 단어는 보관함에 넣는다. 복습 일정은 새 단어 기본값 그대로 두고 SRS 흐름에 맡긴다.
    @discardableResult
    static func addDay(
        kept: [VocaWordJSON],
        setAside: [VocaWordJSON],
        existingDays: [VocabularyDay],
        in context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> VocabularyDay {
        guard !hasAddedToday(existingDays: existingDays, now: now, calendar: calendar) else {
            throw BundledWordPackError.alreadyAddedToday
        }
        guard !kept.isEmpty else { throw BundledWordPackError.exhausted }

        for draft in setAside {
            context.insert(SetAsideWord(english: draft.english, meaningKo: draft.meaningKo, createdAt: now))
        }

        let day = DayFactory.createNextDay(existingDays: existingDays, in: context)
        day.createdAt = now
        day.source = daySource
        for draft in kept {
            var fresh = draft
            fresh.id = UUID()
            let word = GeneratedWordDraftMapper.makeEntity(from: fresh, day: day, now: now)
            context.insert(word)
            day.appendWord(word)
        }
        if let error = context.saveReportingError() {
            throw error
        }
        return day
    }
}

/// 오늘의 단어 검수 한 판. 후보를 한 장씩 "넣기/보관"으로 판단하고, 보관한 만큼 다음 후보를 뒤에 붙여
/// 넣을 단어가 `target`개가 되게 한다(후보가 모자라면 그보다 적게). 화면과 분리해 테스트할 수 있게 둔다.
///
/// 불변식: `queue[..<decisions.count]` 는 판단됐고, 그 뒤는 판단되지 않았다.
struct BundledDayReview: Equatable {
    enum Decision: Equatable {
        case keep
        /// `refilled`: 이 보관 때문에 대기열 끝에 후보를 하나 붙였는지. 되돌릴 때 함께 뺀다.
        case setAside(refilled: Bool)
    }

    private let pool: [VocaWordJSON]
    private(set) var queue: [VocaWordJSON]
    private(set) var decisions: [Decision] = []

    init(candidates: [VocaWordJSON], target: Int = BundledWordPack.dailyCount) {
        pool = candidates
        queue = Array(candidates.prefix(target))
    }

    var currentIndex: Int { decisions.count }
    var current: VocaWordJSON? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }
    var isEmpty: Bool { queue.isEmpty }
    var isComplete: Bool { !queue.isEmpty && currentIndex >= queue.count }
    var canGoBack: Bool { !decisions.isEmpty }

    /// 끝까지 검수했을 때 데이에 들어갈 단어 수. 보관해도 보충되므로 후보가 모자랄 때만 줄어든다.
    var targetCount: Int { queue.count - setAside.count }

    var kept: [VocaWordJSON] {
        zip(queue, decisions).compactMap { word, decision in decision == .keep ? word : nil }
    }

    var setAside: [VocaWordJSON] {
        zip(queue, decisions).compactMap { word, decision in decision == .keep ? nil : word }
    }

    mutating func keep() {
        guard current != nil else { return }
        decisions.append(.keep)
    }

    mutating func setAsideCurrent() {
        guard current != nil else { return }
        let canRefill = queue.count < pool.count
        if canRefill {
            queue.append(pool[queue.count])
        }
        decisions.append(.setAside(refilled: canRefill))
    }

    /// 남은 카드를 모두 넣기로 판단한다.
    mutating func keepRemaining() {
        while current != nil {
            keep()
        }
    }

    mutating func goBack() {
        guard let last = decisions.popLast() else { return }
        if last == .setAside(refilled: true) {
            queue.removeLast()
        }
    }
}
