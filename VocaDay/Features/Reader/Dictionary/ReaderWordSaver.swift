import Foundation
import SwiftData

enum ReaderWordSaveError: LocalizedError, Equatable {
    case duplicate(dayTitle: String)
    case notSavable(WordDataCheck.Issue)

    var errorDescription: String? {
        switch self {
        case .duplicate(let dayTitle): "이미 \(dayTitle)에 있는 단어예요."
        case .notSavable(let issue): issue.message
        }
    }
}

/// 리더에서 찾은 단어를 내 단어장에 넣는다. 누른 문장이 예문, 그 번역이 예문 번역이 된다.
///
/// 넣는 곳(임시안): 책에서 모은 단어를 모으는 데이 하나 (`daySource`). 없으면 만든다.
/// 단어 일정(srs*)은 새 단어 기본값 그대로 두고 SRS 흐름에 맡긴다 (`GeneratedWordDraftMapper.makeEntity`).
enum ReaderWordSaver {
    static let daySource = "readerBook"
    static let dayTitle = "책에서 모은 단어"

    static func draft(for result: WordLookupResult, context: WordTapContext, book: BookDocument) -> VocaWordJSON {
        let translation = context.sentenceTranslation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let source = "책 · \(book.title)"
        return VocaWordJSON(
            english: result.headword,
            meaningKo: result.meaningForSaving,
            exampleEn: context.sentence.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleKo: translation,
            note: result.note ?? "",
            toeicTag: result.toeicTag.map { "\($0) · \(source)" } ?? source
        )
    }

    static func issues(for draft: VocaWordJSON) -> [WordDataCheck.Issue] {
        WordDataCheck.issues(for: draft)
    }

    /// 같은 철자의 단어가 들어 있는 데이 이름. 단어 추가 화면처럼 모든 데이에서 철자로 막는다.
    static func existingDayTitle(for english: String, in days: [VocabularyDay]) -> String? {
        let key = english.normalizedEnglish
        guard !key.isEmpty else { return nil }
        return days.first { day in day.wordList.contains { $0.english.normalizedEnglish == key } }?.title
    }

    static func collectionDay(in days: [VocabularyDay]) -> VocabularyDay? {
        days.first { $0.source == daySource }
    }

    @discardableResult
    static func add(
        _ draft: VocaWordJSON,
        existingDays: [VocabularyDay],
        in context: ModelContext,
        now: Date = Date()
    ) throws -> VocabularyDay {
        if let blocking = issues(for: draft).first(where: \.isBlocking) {
            throw ReaderWordSaveError.notSavable(blocking)
        }
        if let title = existingDayTitle(for: draft.english, in: existingDays) {
            throw ReaderWordSaveError.duplicate(dayTitle: title)
        }

        let day: VocabularyDay
        if let existing = collectionDay(in: existingDays) {
            day = existing
        } else {
            day = DayFactory.createDay(title: dayTitle, in: context)
            day.createdAt = now
            day.source = daySource
        }
        var fresh = draft
        fresh.id = UUID()
        let word = GeneratedWordDraftMapper.makeEntity(from: fresh, day: day, now: now)
        context.insert(word)
        day.appendWord(word)
        if let error = context.saveReportingError() {
            throw error
        }
        return day
    }
}
