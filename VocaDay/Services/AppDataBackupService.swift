import Foundation
import SwiftData

enum AppDataArchiveType: String, Codable {
    case allAppData
    case vocabularyDay
    case lcDictationDay
    case grammarNote
}

struct AppDataArchive: Codable {
    var schemaVersion: Int
    var createdAt: Date
    var appVersion: String
    var type: AppDataArchiveType
    var vocabularyDays: [VocabularyDayArchive]
    var lcDictationDays: [LCDictationDayArchive]
    var grammarNotes: [GrammarNoteArchive]
    var customStudyPages: [CustomStudyPageArchive]

    init(
        schemaVersion: Int = 2,
        createdAt: Date = Date(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        type: AppDataArchiveType,
        vocabularyDays: [VocabularyDayArchive] = [],
        lcDictationDays: [LCDictationDayArchive] = [],
        grammarNotes: [GrammarNoteArchive] = [],
        customStudyPages: [CustomStudyPageArchive] = []
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.type = type
        self.vocabularyDays = vocabularyDays
        self.lcDictationDays = lcDictationDays
        self.grammarNotes = grammarNotes
        self.customStudyPages = customStudyPages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        type = try container.decodeIfPresent(AppDataArchiveType.self, forKey: .type) ?? .allAppData
        vocabularyDays = try container.decodeIfPresent([VocabularyDayArchive].self, forKey: .vocabularyDays) ?? []
        lcDictationDays = try container.decodeIfPresent([LCDictationDayArchive].self, forKey: .lcDictationDays) ?? []
        grammarNotes = try container.decodeIfPresent([GrammarNoteArchive].self, forKey: .grammarNotes) ?? []
        customStudyPages = try container.decodeIfPresent([CustomStudyPageArchive].self, forKey: .customStudyPages) ?? []
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
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "가져온 LC 데이"
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

struct GrammarNoteArchive: Codable, Identifiable {
    var id: UUID
    var title: String
    var markdown: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        markdown: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.markdown = markdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "가져온 문법 노트"
        markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}

struct CustomStudyPageArchive: Codable, Identifiable {
    var id: UUID
    var title: String
    var iconName: String
    var kindRawValue: String
    var markdown: String
    var columnsJSON: String
    var rowsJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String = "doc.richtext",
        kindRawValue: String = StudyPageKind.markdown.rawValue,
        markdown: String = "",
        columnsJSON: String = "[]",
        rowsJSON: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.kindRawValue = kindRawValue
        self.markdown = markdown
        self.columnsJSON = columnsJSON
        self.rowsJSON = rowsJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "가져온 학습 페이지"
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "doc.richtext"
        kindRawValue = try container.decodeIfPresent(String.self, forKey: .kindRawValue) ?? StudyPageKind.markdown.rawValue
        markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        columnsJSON = try container.decodeIfPresent(String.self, forKey: .columnsJSON) ?? "[]"
        rowsJSON = try container.decodeIfPresent(String.self, forKey: .rowsJSON) ?? "[]"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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
    let grammarNotesToCreate: Int
    let grammarNotesToUpdate: Int
    let customPagesToCreate: Int
    let customPagesToUpdate: Int

    var isEmpty: Bool {
        vocabularyDaysToCreate == 0 &&
        vocabularyDaysToUpdate == 0 &&
        wordsToCreate == 0 &&
        wordsToUpdate == 0 &&
        lcDaysToCreate == 0 &&
        lcDaysToUpdate == 0 &&
        notesToCreate == 0 &&
        notesToUpdate == 0 &&
        grammarNotesToCreate == 0 &&
        grammarNotesToUpdate == 0 &&
        customPagesToCreate == 0 &&
        customPagesToUpdate == 0
    }

    var summary: String {
        if isEmpty {
            return "반영할 변경 사항이 없습니다."
        }

        return [
            "단어 데이: 새로 만들기 \(vocabularyDaysToCreate)개, 업데이트 \(vocabularyDaysToUpdate)개",
            "단어: 새로 만들기 \(wordsToCreate)개, 업데이트 \(wordsToUpdate)개",
            "LC 노트: 새로 만들기 \(lcDaysToCreate)개, 업데이트 \(lcDaysToUpdate)개",
            "받아쓰기 줄: 새로 만들기 \(notesToCreate)개, 업데이트 \(notesToUpdate)개",
            "문법 노트: 새로 만들기 \(grammarNotesToCreate)개, 업데이트 \(grammarNotesToUpdate)개",
            "내 학습 페이지: 새로 만들기 \(customPagesToCreate)개, 업데이트 \(customPagesToUpdate)개"
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
    static func archiveAll(
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay],
        grammarNotes: [GrammarNote],
        customStudyPages: [CustomStudyPage] = []
    ) -> AppDataArchive {
        AppDataArchive(
            type: .allAppData,
            vocabularyDays: vocabularyDays.sortedByCreatedAt().map(Self.archiveVocabularyDay),
            lcDictationDays: lcDays.sortedByCreatedAt().map(Self.archiveLCDictationDay),
            grammarNotes: grammarNotes.sortedByUpdatedAt().map(Self.archiveGrammarNoteRecord),
            customStudyPages: customStudyPages
                .sorted { $0.createdAt < $1.createdAt }
                .map(Self.archiveCustomStudyPage)
        )
    }

    static func archiveVocabularyDay(_ day: VocabularyDay) -> AppDataArchive {
        AppDataArchive(type: .vocabularyDay, vocabularyDays: [archiveVocabularyDay(day)])
    }

    static func archiveLCDictationDay(_ day: LCDictationDay) -> AppDataArchive {
        AppDataArchive(type: .lcDictationDay, lcDictationDays: [archiveLCDictationDay(day)])
    }

    static func archiveGrammarNote(_ note: GrammarNote) -> AppDataArchive {
        AppDataArchive(type: .grammarNote, grammarNotes: [archiveGrammarNoteRecord(note)])
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
        let archive = try decoder.decode(AppDataArchive.self, from: data)
        guard archive.schemaVersion <= 2 else {
            throw AppDataBackupError.unsupportedVersion(archive.schemaVersion)
        }
        return archive
    }

    static func preview(
        _ archive: AppDataArchive,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay],
        grammarNotes: [GrammarNote],
        customStudyPages: [CustomStudyPage] = []
    ) -> AppDataImportPreview {
        let existingVocabularyDayIDs = Set(vocabularyDays.map(\.id))
        let existingWordIDs = Set(vocabularyDays.flatMap { $0.wordList.map(\.id) })
        let existingLCDayIDs = Set(lcDays.map(\.id))
        let existingNoteIDs = Set(lcDays.flatMap { $0.noteList.map(\.id) })
        let existingGrammarNoteIDs = Set(grammarNotes.map(\.id))
        let existingCustomPageIDs = Set(customStudyPages.map(\.id))

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
            notesToUpdate: incomingNoteIDs.filter { existingNoteIDs.contains($0) }.count,
            grammarNotesToCreate: archive.grammarNotes.filter { !existingGrammarNoteIDs.contains($0.id) }.count,
            grammarNotesToUpdate: archive.grammarNotes.filter { existingGrammarNoteIDs.contains($0.id) }.count,
            customPagesToCreate: archive.customStudyPages.filter { !existingCustomPageIDs.contains($0.id) }.count,
            customPagesToUpdate: archive.customStudyPages.filter { existingCustomPageIDs.contains($0.id) }.count
        )
    }

    static func applyUpsert(
        _ archive: AppDataArchive,
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay],
        grammarNotes: [GrammarNote],
        customStudyPages: [CustomStudyPage] = []
    ) throws {
        var vocabularyDaysByID = Dictionary(uniqueKeysWithValues: vocabularyDays.map { ($0.id, $0) })
        var wordsByID = Dictionary(uniqueKeysWithValues: vocabularyDays.flatMap { day in
            day.wordList.map { ($0.id, $0) }
        })
        var lcDaysByID = Dictionary(uniqueKeysWithValues: lcDays.map { ($0.id, $0) })
        var notesByID = Dictionary(uniqueKeysWithValues: lcDays.flatMap { day in
            day.noteList.map { ($0.id, $0) }
        })
        var grammarNotesByID = Dictionary(uniqueKeysWithValues: grammarNotes.map { ($0.id, $0) })
        var customPagesByID = Dictionary(uniqueKeysWithValues: customStudyPages.map { ($0.id, $0) })

        for dayArchive in archive.vocabularyDays {
            let day = vocabularyDaysByID[dayArchive.id] ?? {
                let newDay = VocabularyDay(id: dayArchive.id, title: dayArchive.title, createdAt: dayArchive.createdAt)
                context.insert(newDay)
                vocabularyDaysByID[dayArchive.id] = newDay
                return newDay
            }()

            day.title = dayArchive.title
            day.createdAt = dayArchive.createdAt
            day.reviewSessionCount = dayArchive.reviewSessionCount
            day.reviewedWordCount = dayArchive.reviewedWordCount
            day.lastReviewedAt = dayArchive.lastReviewedAt

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

        for noteArchive in archive.grammarNotes {
            let note = grammarNotesByID[noteArchive.id] ?? {
                let newNote = GrammarNote(id: noteArchive.id, title: noteArchive.title)
                context.insert(newNote)
                grammarNotesByID[noteArchive.id] = newNote
                return newNote
            }()

            apply(noteArchive, to: note)
        }

        for pageArchive in archive.customStudyPages {
            let page = customPagesByID[pageArchive.id] ?? {
                let newPage = CustomStudyPage(
                    id: pageArchive.id,
                    title: pageArchive.title,
                    iconName: pageArchive.iconName,
                    kind: StudyPageKind(rawValue: pageArchive.kindRawValue) ?? .markdown,
                    createdAt: pageArchive.createdAt,
                    updatedAt: pageArchive.updatedAt
                )
                context.insert(newPage)
                customPagesByID[pageArchive.id] = newPage
                return newPage
            }()

            apply(pageArchive, to: page)
        }

        try context.save()
    }

    static func deleteAll(
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        lcDays: [LCDictationDay],
        grammarNotes: [GrammarNote],
        customStudyPages: [CustomStudyPage] = []
    ) throws {
        for day in vocabularyDays {
            context.delete(day)
        }
        for day in lcDays {
            context.delete(day)
        }
        for note in grammarNotes {
            context.delete(note)
        }
        for page in customStudyPages {
            context.delete(page)
        }
        try context.save()
    }

    private static func archiveVocabularyDay(_ day: VocabularyDay) -> VocabularyDayArchive {
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

    private static func archiveGrammarNoteRecord(_ note: GrammarNote) -> GrammarNoteArchive {
        GrammarNoteArchive(
            id: note.id,
            title: note.title,
            markdown: note.markdown,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            isFavorite: note.isFavorite,
            isCompleted: note.isCompleted
        )
    }

    private static func archiveCustomStudyPage(_ page: CustomStudyPage) -> CustomStudyPageArchive {
        CustomStudyPageArchive(
            id: page.id,
            title: page.title,
            iconName: page.iconName,
            kindRawValue: page.kindRawValue,
            markdown: page.markdown,
            columnsJSON: page.columnsJSON,
            rowsJSON: page.rowsJSON,
            createdAt: page.createdAt,
            updatedAt: page.updatedAt
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

    private static func apply(_ archive: GrammarNoteArchive, to note: GrammarNote) {
        note.id = archive.id
        note.title = archive.title
        note.markdown = archive.markdown
        note.createdAt = archive.createdAt
        note.updatedAt = archive.updatedAt
        note.isFavorite = archive.isFavorite
        note.isCompleted = archive.isCompleted
    }

    private static func apply(_ archive: CustomStudyPageArchive, to page: CustomStudyPage) {
        page.id = archive.id
        page.title = archive.title
        page.iconName = archive.iconName
        page.kindRawValue = StudyPageKind(rawValue: archive.kindRawValue)?.rawValue ?? StudyPageKind.markdown.rawValue
        page.markdown = archive.markdown
        page.columnsJSON = archive.columnsJSON
        page.rowsJSON = archive.rowsJSON
        page.createdAt = archive.createdAt
        page.updatedAt = archive.updatedAt
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

private extension Array where Element == GrammarNote {
    func sortedByUpdatedAt() -> [GrammarNote] {
        sorted { $0.updatedAt > $1.updatedAt }
    }
}
