import Foundation
import SwiftData

enum AppDataArchiveType: String, Codable {
    case allAppData
    case vocabularyDay

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = AppDataArchiveType(rawValue: value) ?? .allAppData
    }
}

struct AppDataArchive: Codable {
    var schemaVersion: Int
    var createdAt: Date
    var appVersion: String
    var type: AppDataArchiveType
    var vocabularyDays: [VocabularyDayArchive]

    init(
        schemaVersion: Int = 2,
        createdAt: Date = Date(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        type: AppDataArchiveType,
        vocabularyDays: [VocabularyDayArchive] = []
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.type = type
        self.vocabularyDays = vocabularyDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        type = try container.decodeIfPresent(AppDataArchiveType.self, forKey: .type) ?? .allAppData
        vocabularyDays = try container.decodeIfPresent([VocabularyDayArchive].self, forKey: .vocabularyDays) ?? []
    }
}

struct VocabularyDayArchive: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var reviewSessionCount: Int
    var reviewedWordCount: Int
    var lastReviewedAt: Date?
    var words: [VocaWordArchive]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        reviewSessionCount: Int = 0,
        reviewedWordCount: Int = 0,
        lastReviewedAt: Date? = nil,
        words: [VocaWordArchive] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.reviewSessionCount = reviewSessionCount
        self.reviewedWordCount = reviewedWordCount
        self.lastReviewedAt = lastReviewedAt
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "가져온 데이"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        reviewSessionCount = try container.decodeIfPresent(Int.self, forKey: .reviewSessionCount) ?? 0
        reviewedWordCount = try container.decodeIfPresent(Int.self, forKey: .reviewedWordCount) ?? 0
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        words = try container.decodeIfPresent([VocaWordArchive].self, forKey: .words) ?? []
    }
}

struct VocaWordArchive: Codable, Identifiable {
    var id: UUID
    var english: String
    var meaningKo: String
    var exampleEn: String
    var exampleKo: String
    var note: String
    var toeicTag: String
    var createdAt: Date
    var reviewCount: Int
    var correctCount: Int
    var wrongCount: Int
    var masteryLevel: Int
    var status: String
    var nextReviewAt: Date
    var lastReviewedAt: Date?

    init(
        id: UUID = UUID(), english: String, meaningKo: String = "", exampleEn: String = "",
        exampleKo: String = "", note: String = "", toeicTag: String = "", createdAt: Date = Date(),
        reviewCount: Int = 0, correctCount: Int = 0, wrongCount: Int = 0, masteryLevel: Int = 0,
        status: String = WordStatus.new.rawValue, nextReviewAt: Date = Date(), lastReviewedAt: Date? = nil
    ) {
        self.id = id
        self.english = english
        self.meaningKo = meaningKo
        self.exampleEn = exampleEn
        self.exampleKo = exampleKo
        self.note = note
        self.toeicTag = toeicTag
        self.createdAt = createdAt
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.masteryLevel = masteryLevel
        self.status = status
        self.nextReviewAt = nextReviewAt
        self.lastReviewedAt = lastReviewedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        english = try container.decodeIfPresent(String.self, forKey: .english) ?? ""
        meaningKo = try container.decodeIfPresent(String.self, forKey: .meaningKo) ?? ""
        exampleEn = try container.decodeIfPresent(String.self, forKey: .exampleEn) ?? ""
        exampleKo = try container.decodeIfPresent(String.self, forKey: .exampleKo) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        toeicTag = try container.decodeIfPresent(String.self, forKey: .toeicTag) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        correctCount = try container.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        wrongCount = try container.decodeIfPresent(Int.self, forKey: .wrongCount) ?? 0
        masteryLevel = try container.decodeIfPresent(Int.self, forKey: .masteryLevel) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? WordStatus.new.rawValue
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt) ?? Date()
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
    }
}

struct AppDataImportPreview {
    let vocabularyDaysToCreate: Int
    let vocabularyDaysToUpdate: Int
    let wordsToCreate: Int
    let wordsToUpdate: Int

    var isEmpty: Bool {
        vocabularyDaysToCreate == 0 && vocabularyDaysToUpdate == 0 && wordsToCreate == 0 && wordsToUpdate == 0
    }

    var summary: String {
        guard !isEmpty else { return "반영할 변경 사항이 없습니다." }
        return [
            "단어 데이: 새로 만들기 \(vocabularyDaysToCreate)개, 업데이트 \(vocabularyDaysToUpdate)개",
            "단어: 새로 만들기 \(wordsToCreate)개, 업데이트 \(wordsToUpdate)개"
        ].joined(separator: "\n")
    }
}

enum AppDataBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "이 백업 파일은 더 새로운 VocaDay 형식(버전 \(version))으로 만들어졌습니다. 앱을 업데이트한 뒤 다시 시도하세요."
        case .invalidFile:
            "선택한 파일을 VocaDay 백업으로 읽을 수 없습니다."
        }
    }
}

@MainActor
enum AppDataBackupService {
    static func archiveAll(vocabularyDays: [VocabularyDay]) -> AppDataArchive {
        AppDataArchive(
            type: .allAppData,
            vocabularyDays: vocabularyDays.sortedByCreatedAt().map(Self.makeVocabularyDayArchive)
        )
    }

    static func archiveVocabularyDay(_ day: VocabularyDay) -> AppDataArchive {
        AppDataArchive(type: .vocabularyDay, vocabularyDays: [makeVocabularyDayArchive(day)])
    }

    static func encode(_ archive: AppDataArchive) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) throws -> AppDataArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(AppDataArchive.self, from: Data(json.utf8))
        guard archive.schemaVersion <= 2 else {
            throw AppDataBackupError.unsupportedVersion(archive.schemaVersion)
        }
        return archive
    }

    static func preview(_ archive: AppDataArchive, vocabularyDays: [VocabularyDay]) -> AppDataImportPreview {
        let existingDayIDs = Set(vocabularyDays.map(\.id))
        let existingWordIDs = Set(vocabularyDays.flatMap { $0.wordList.map(\.id) })
        let incomingWordIDs = archive.vocabularyDays.flatMap { $0.words.map(\.id) }

        return AppDataImportPreview(
            vocabularyDaysToCreate: archive.vocabularyDays.filter { !existingDayIDs.contains($0.id) }.count,
            vocabularyDaysToUpdate: archive.vocabularyDays.filter { existingDayIDs.contains($0.id) }.count,
            wordsToCreate: incomingWordIDs.filter { !existingWordIDs.contains($0) }.count,
            wordsToUpdate: incomingWordIDs.filter { existingWordIDs.contains($0) }.count
        )
    }

    static func applyUpsert(
        _ archive: AppDataArchive,
        in context: ModelContext,
        vocabularyDays: [VocabularyDay]
    ) throws {
        var daysByID = Dictionary(uniqueKeysWithValues: vocabularyDays.map { ($0.id, $0) })
        var wordsByID = Dictionary(uniqueKeysWithValues: vocabularyDays.flatMap { day in
            day.wordList.map { ($0.id, $0) }
        })

        for dayArchive in archive.vocabularyDays {
            let day = daysByID[dayArchive.id] ?? {
                let newDay = VocabularyDay(id: dayArchive.id, title: dayArchive.title, createdAt: dayArchive.createdAt)
                context.insert(newDay)
                daysByID[dayArchive.id] = newDay
                return newDay
            }()

            day.title = dayArchive.title
            day.createdAt = dayArchive.createdAt
            day.reviewSessionCount = dayArchive.reviewSessionCount
            day.reviewedWordCount = dayArchive.reviewedWordCount
            day.lastReviewedAt = dayArchive.lastReviewedAt

            for wordArchive in dayArchive.words {
                let word = wordsByID[wordArchive.id] ?? {
                    let newWord = VocaWord(id: wordArchive.id, english: wordArchive.english, day: day)
                    context.insert(newWord)
                    wordsByID[wordArchive.id] = newWord
                    return newWord
                }()

                apply(wordArchive, to: word)
                if word.day?.id != day.id {
                    word.day?.removeWord(word)
                    word.day = day
                }
                if !day.wordList.contains(where: { $0.id == word.id }) {
                    day.appendWord(word)
                }
            }
        }
        try context.save()
    }

    static func deleteAll(in context: ModelContext, vocabularyDays: [VocabularyDay]) throws {
        for day in vocabularyDays {
            context.delete(day)
        }
        try context.save()
    }

    private static func makeVocabularyDayArchive(_ day: VocabularyDay) -> VocabularyDayArchive {
        VocabularyDayArchive(
            id: day.id,
            title: day.title,
            createdAt: day.createdAt,
            reviewSessionCount: day.reviewSessionCount,
            reviewedWordCount: day.reviewedWordCount,
            lastReviewedAt: day.lastReviewedAt,
            words: day.wordList.sortedByCreatedAt().map { word in
                VocaWordArchive(
                    id: word.id,
                    english: word.english,
                    meaningKo: word.meaningKo,
                    exampleEn: word.exampleEn,
                    exampleKo: word.exampleKo,
                    note: word.note,
                    toeicTag: word.toeicTag,
                    createdAt: word.createdAt,
                    reviewCount: word.reviewCount,
                    correctCount: word.correctCount,
                    wrongCount: word.wrongCount,
                    masteryLevel: word.masteryLevel,
                    status: word.status,
                    nextReviewAt: word.nextReviewAt,
                    lastReviewedAt: word.lastReviewedAt
                )
            }
        )
    }

    private static func apply(_ archive: VocaWordArchive, to word: VocaWord) {
        word.english = archive.english
        word.meaningKo = archive.meaningKo
        word.exampleEn = archive.exampleEn
        word.exampleKo = archive.exampleKo
        word.note = archive.note
        word.toeicTag = archive.toeicTag
        word.createdAt = archive.createdAt
        word.reviewCount = archive.reviewCount
        word.correctCount = archive.correctCount
        word.wrongCount = archive.wrongCount
        word.masteryLevel = max(0, min(archive.masteryLevel, 4))
        word.status = WordStatus(rawValue: archive.status)?.rawValue ?? WordStatus.new.rawValue
        word.nextReviewAt = archive.nextReviewAt
        word.lastReviewedAt = archive.lastReviewedAt
    }
}

private extension Array where Element == VocabularyDay {
    func sortedByCreatedAt() -> [VocabularyDay] {
        sorted { $0.createdAt < $1.createdAt }
    }
}

private extension Array where Element == VocaWord {
    func sortedByCreatedAt() -> [VocaWord] {
        sorted { $0.createdAt < $1.createdAt }
    }
}
