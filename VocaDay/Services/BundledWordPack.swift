import Foundation
import SwiftData

enum BundledWordPackError: LocalizedError {
    case resourceNotFound
    case exhausted

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "번들에 포함된 기본 단어 파일을 찾을 수 없습니다."
        case .exhausted:
            "기본 단어장의 단어를 모두 추가했어요."
        }
    }
}

/// 앱에 내장된 TOEIC 단어장(BundledWords.json). 파일 순서는 scripts/build_bundled_words.py 가 고정 시드로 섞은 순서다.
/// 진행 위치를 따로 저장하지 않고, 이미 어느 데이에든 있는 단어를 건너뛰어 다음 단어를 고른다.
/// 그래서 기기 간 동기화와 데이 삭제에도 따로 맞출 상태가 없다.
enum BundledWordPack {
    static let dailyCount = 30

    static func loadWords(bundle: Bundle = .main) throws -> [VocaWordJSON] {
        guard let url = bundle.url(forResource: "BundledWords", withExtension: "json") else {
            throw BundledWordPackError.resourceNotFound
        }
        return try JSONWordParser.decode(String(decoding: try Data(contentsOf: url), as: UTF8.self))
    }

    /// 기존 단어에 없는 것만 파일 순서대로 `count`개.
    static func nextWords(from pack: [VocaWordJSON], existingDays: [VocabularyDay], count: Int = dailyCount) -> [VocaWordJSON] {
        let existing = Set(existingDays.flatMap(\.wordList).map { $0.english.normalizedEnglish })
        return Array(pack.lazy.filter { !existing.contains($0.english.normalizedEnglish) }.prefix(count))
    }

    static func remainingCount(in pack: [VocaWordJSON], existingDays: [VocabularyDay]) -> Int {
        let existing = Set(existingDays.flatMap(\.wordList).map { $0.english.normalizedEnglish })
        return pack.filter { !existing.contains($0.english.normalizedEnglish) }.count
    }

    /// 다음 단어들로 새 데이를 만든다. 복습 일정은 새 단어 기본값 그대로 두고 SRS 흐름에 맡긴다.
    @discardableResult
    static func addNextDay(
        existingDays: [VocabularyDay],
        in context: ModelContext,
        pack: [VocaWordJSON]? = nil,
        now: Date = Date()
    ) throws -> VocabularyDay {
        let words = nextWords(from: try pack ?? loadWords(), existingDays: existingDays)
        guard !words.isEmpty else { throw BundledWordPackError.exhausted }

        let day = DayFactory.createNextDay(existingDays: existingDays, in: context)
        for draft in words {
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
