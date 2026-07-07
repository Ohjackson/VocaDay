import Foundation
import SwiftData

enum AppDataArchiveType: String, Codable {
    case allAppData
    case vocabularyDay
    case lcDictationDay
}

struct AppDataArchive: Codable {
    var schemaVersion: Int
    var type: AppDataArchiveType
    var vocabularyDays: [VocabularyDayArchive]
    var lcDictationDays: [LCDictationDayArchive]

    init(
        schemaVersion: Int = 1,
        type: AppDataArchiveType,
        vocabularyDays: [VocabularyDayArchive] = [],
        lcDictationDays: [LCDictationDayArchive] = []
    ) {
        self.schemaVersion = schemaVersion
        self.type = type
        self.vocabularyDays = vocabularyDays
        self.lcDictationDays = lcDictationDays
    }
}

struct VocabularyDayArchive: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var words: [VocaWordArchive]

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), words: [VocaWordArchive] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Imported Day"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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
        id: UUID = UUID(),
        english: String,
        meaningKo: String = "",
        exampleEn: String = "",
        exampleKo: String = "",
        note: String = "",
        toeicTag: String = "",
        createdAt: Date = Date(),
        reviewCount: Int = 0,
        correctCount: Int = 0,
        wrongCount: Int = 0,
        masteryLevel: Int = 0,
        status: String = WordStatus.new.rawValue,
        nextReviewAt: Date = Date(),
        lastReviewedAt: Date? = nil
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

struct LCDictationDayArchive: Codable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var notes: [LCDictationNoteArchive]

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), notes: [LCDictationNoteArchive] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Imported LC Day"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        notes = try container.decodeIfPresent([LCDictationNoteArchive].self, forKey: .notes) ?? []
    }
}

struct LCDictationNoteArchive: Codable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct AppDataImportPreview {
    let vocabularyDaysToCreate: Int
    let vocabularyDaysToUpdate: Int
    let wordsToCreate: Int
    let wordsToUpdate: Int
    let lcDaysToCreate: Int
    let lcDaysToUpdate: Int
    let notesToCreate: Int
    let notesToUpdate: Int

    var isEmpty: Bool {
        vocabularyDaysToCreate == 0 &&
        vocabularyDaysToUpdate == 0 &&
        wordsToCreate == 0 &&
        wordsToUpdate == 0 &&
        lcDaysToCreate == 0 &&
        lcDaysToUpdate == 0 &&
        notesToCreate == 0 &&
        notesToUpdate == 0
    }

    var summary: String {
        if isEmpty {
            return String(localized: "No matching changes found.")
        }

        return [
            String(format: String(localized: "Vocabulary Days: %lld new, %lld update"), vocabularyDaysToCreate, vocabularyDaysToUpdate),
            String(format: String(localized: "Words: %lld new, %lld update"), wordsToCreate, wordsToUpdate),
            String(format: String(localized: "LC Dictation Days: %lld new, %lld update"), lcDaysToCreate, lcDaysToUpdate),
            String(format: String(localized: "LC Notes: %lld new, %lld update"), notesToCreate, notesToUpdate)
        ].joined(separator: "\n")
    }
}

@MainActor
enum AppDataBackupService {
    static func archiveAll(vocabularyDays: [VocabularyDay], lcDays: [LCDictationDay]) -> AppDataArchive {
        AppDataArchive(
            type: .allAppData,
            vocabularyDays: vocabularyDays.sortedByCreatedAt().map(Self.archiveVocabularyDay),
            lcDictationDays: lcDays.sortedByCreatedAt().map(Self.archiveLCDictationDay)
        )
    }

    static func archiveVocabularyDay(_ day: VocabularyDay) -> AppDataArchive {
        AppDataArchive(type: .vocabularyDay, vocabularyDays: [archiveVocabularyDay(day)])
    }

    static func archiveLCDictationDay(_ day: LCDictationDay) -> AppDataArchive {
        AppDataArchive(type: .lcDictationDay, lcDictationDays: [archiveLCDictationDay(day)])
    }

    static func encode(_ archive: AppDataArchive) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) throws -> AppDataArchive {
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppDataArchive.self, from: data)
    }

    static func preview(
        _ archive: AppDataArchive,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay]
    ) -> AppDataImportPreview {
        let existingVocabularyDayIDs = Set(vocabularyDays.map(\.id))
        let existingWordIDs = Set(vocabularyDays.flatMap { $0.wordList.map(\.id) })
        let existingLCDayIDs = Set(lcDays.map(\.id))
        let existingNoteIDs = Set(lcDays.flatMap { $0.noteList.map(\.id) })

        let incomingWordIDs = archive.vocabularyDays.flatMap { $0.words.map(\.id) }
        let incomingNoteIDs = archive.lcDictationDays.flatMap { $0.notes.map(\.id) }

        return AppDataImportPreview(
            vocabularyDaysToCreate: archive.vocabularyDays.filter { !existingVocabularyDayIDs.contains($0.id) }.count,
            vocabularyDaysToUpdate: archive.vocabularyDays.filter { existingVocabularyDayIDs.contains($0.id) }.count,
            wordsToCreate: incomingWordIDs.filter { !existingWordIDs.contains($0) }.count,
            wordsToUpdate: incomingWordIDs.filter { existingWordIDs.contains($0) }.count,
            lcDaysToCreate: archive.lcDictationDays.filter { !existingLCDayIDs.contains($0.id) }.count,
            lcDaysToUpdate: archive.lcDictationDays.filter { existingLCDayIDs.contains($0.id) }.count,
            notesToCreate: incomingNoteIDs.filter { !existingNoteIDs.contains($0) }.count,
            notesToUpdate: incomingNoteIDs.filter { existingNoteIDs.contains($0) }.count
        )
    }

    static func applyUpsert(
        _ archive: AppDataArchive,
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay]
    ) throws {
        var vocabularyDaysByID = Dictionary(uniqueKeysWithValues: vocabularyDays.map { ($0.id, $0) })
        var wordsByID = Dictionary(uniqueKeysWithValues: vocabularyDays.flatMap { day in
            day.wordList.map { ($0.id, $0) }
        })
        var lcDaysByID = Dictionary(uniqueKeysWithValues: lcDays.map { ($0.id, $0) })
        var notesByID = Dictionary(uniqueKeysWithValues: lcDays.flatMap { day in
            day.noteList.map { ($0.id, $0) }
        })

        for dayArchive in archive.vocabularyDays {
            let day = vocabularyDaysByID[dayArchive.id] ?? {
                let newDay = VocabularyDay(id: dayArchive.id, title: dayArchive.title, createdAt: dayArchive.createdAt)
                context.insert(newDay)
                vocabularyDaysByID[dayArchive.id] = newDay
                return newDay
            }()

            day.title = dayArchive.title
            day.createdAt = dayArchive.createdAt

            for wordArchive in dayArchive.words {
                let word = wordsByID[wordArchive.id] ?? {
                    let newWord = VocaWord(english: wordArchive.english, day: day)
                    newWord.id = wordArchive.id
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

        for dayArchive in archive.lcDictationDays {
            let day = lcDaysByID[dayArchive.id] ?? {
                let newDay = LCDictationDay(id: dayArchive.id, title: dayArchive.title, createdAt: dayArchive.createdAt)
                context.insert(newDay)
                lcDaysByID[dayArchive.id] = newDay
                return newDay
            }()

            day.title = dayArchive.title
            day.createdAt = dayArchive.createdAt

            for noteArchive in dayArchive.notes {
                let note = notesByID[noteArchive.id] ?? {
                    let newNote = LCDictationNote(id: noteArchive.id, day: day)
                    context.insert(newNote)
                    notesByID[noteArchive.id] = newNote
                    return newNote
                }()

                note.text = noteArchive.text
                note.createdAt = noteArchive.createdAt
                if note.day?.id != day.id {
                    note.day = day
                }
                if !day.noteList.contains(where: { $0.id == note.id }) {
                    day.appendNote(note)
                }
            }
        }

        try context.save()
    }

    static func deleteAll(
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay]
    ) throws {
        for day in vocabularyDays {
            context.delete(day)
        }
        for day in lcDays {
            context.delete(day)
        }
        try context.save()
    }

    private static func archiveVocabularyDay(_ day: VocabularyDay) -> VocabularyDayArchive {
        VocabularyDayArchive(
            id: day.id,
            title: day.title,
            createdAt: day.createdAt,
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

    private static func archiveLCDictationDay(_ day: LCDictationDay) -> LCDictationDayArchive {
        LCDictationDayArchive(
            id: day.id,
            title: day.title,
            createdAt: day.createdAt,
            notes: day.noteList.sortedByCreatedAt().map { note in
                LCDictationNoteArchive(
                    id: note.id,
                    text: note.text,
                    createdAt: note.createdAt
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

private extension Array where Element == LCDictationDay {
    func sortedByCreatedAt() -> [LCDictationDay] {
        sorted { $0.createdAt < $1.createdAt }
    }
}

private extension Array where Element == LCDictationNote {
    func sortedByCreatedAt() -> [LCDictationNote] {
        sorted { $0.createdAt < $1.createdAt }
    }
}
