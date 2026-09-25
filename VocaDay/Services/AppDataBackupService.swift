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
    var studyMemos: [StudyMemoArchive]
    var studyPageCategories: [StudyPageCategoryArchive]
    /// 시험보기 학습일 (schema 6+). 단어의 srsNextLearningDay가 이 값에 상대적이라 함께 옮긴다.
    var studyProgress: StudyProgressArchive?
    /// 시험 풀이 로그 (schema 6+, 전체 백업에만).
    var reviewLogs: [ReviewLogArchive]?

    init(
        schemaVersion: Int = AppDataBackupService.currentSchemaVersion,
        createdAt: Date = Date(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        type: AppDataArchiveType,
        vocabularyDays: [VocabularyDayArchive] = [],
        studyMemos: [StudyMemoArchive] = [],
        studyPageCategories: [StudyPageCategoryArchive] = [],
        studyProgress: StudyProgressArchive? = nil,
        reviewLogs: [ReviewLogArchive]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.type = type
        self.vocabularyDays = vocabularyDays
        self.studyMemos = studyMemos
        self.studyPageCategories = studyPageCategories
        self.studyProgress = studyProgress
        self.reviewLogs = reviewLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        type = try container.decodeIfPresent(AppDataArchiveType.self, forKey: .type) ?? .allAppData
        vocabularyDays = try container.decodeIfPresent([VocabularyDayArchive].self, forKey: .vocabularyDays) ?? []
        studyMemos = try container.decodeIfPresent([StudyMemoArchive].self, forKey: .studyMemos) ?? []
        studyPageCategories = try container.decodeIfPresent([StudyPageCategoryArchive].self, forKey: .studyPageCategories) ?? []
        studyProgress = try container.decodeIfPresent(StudyProgressArchive.self, forKey: .studyProgress)
        reviewLogs = try container.decodeIfPresent([ReviewLogArchive].self, forKey: .reviewLogs)
    }
}

struct ReviewLogArchive: Codable {
    var id: UUID
    var wordID: UUID
    var sessionID: UUID
    var learningDay: Int
    var sessionKind: String
    var mode: String
    var isCorrect: Bool
    var outcomeDetail: String
    var stageBefore: Int
    var stageAfter: Int
    var answeredAt: Date
}

struct StudyProgressArchive: Codable {
    var currentLearningDay: Int
}

/// 시험보기 SRS·보강 필드 (schema 6+). 없는 백업을 가져오면 기존 값을 건드리지 않는다.
struct VocaWordQuizArchive: Codable {
    var srsStage: Int = 0
    var srsNextLearningDay: Int = 0
    var srsIdkCount: Int = 0
    var pos: String = ""
    var cefr: String = ""
    var meaningKo: String = ""
    var disambiguationKo: String = ""
    var formsJSON: String = ""
    var termVariantsJSON: String = ""
    var example: String = ""
    var exampleKo: String = ""
    var clozeSentence: String = ""
    var clozeAnswer: String = ""
    var clozeForm: String = ""
    var clozeAcceptedJSON: String = ""
    var nearMissJSON: String = ""
    var enrichmentVersion: Int = 0
    var enrichmentFingerprint: String = ""
}

struct StudyPageCategoryArchive: Codable, Identifiable {
    var id: UUID
    var name: String
    var colorRawValue: String
    var createdAt: Date

    init(id: UUID, name: String, colorRawValue: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.colorRawValue = colorRawValue
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "가져온 분류"
        colorRawValue = try container.decodeIfPresent(String.self, forKey: .colorRawValue) ?? "gray"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct StudyMemoArchive: Codable, Identifiable {
    var id: UUID
    var icon: String
    var coverStyle: String
    var blocksJSON: String
    var richTextData: String
    var plainTextContent: String
    var categoryID: String
    var categoryName: String
    var categoryColor: String
    var typeRawValue: String
    var title: String
    var body: String
    var dictationText: String
    var answerText: String
    var translation: String
    var note: String
    var source: String
    var tags: String
    var isPinned: Bool
    var needsReview: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        icon: String,
        coverStyle: String,
        blocksJSON: String,
        richTextData: String,
        plainTextContent: String,
        categoryID: String,
        categoryName: String,
        categoryColor: String,
        typeRawValue: String,
        title: String,
        body: String,
        dictationText: String,
        answerText: String,
        translation: String,
        note: String,
        source: String,
        tags: String,
        isPinned: Bool,
        needsReview: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.icon = icon
        self.coverStyle = coverStyle
        self.blocksJSON = blocksJSON
        self.richTextData = richTextData
        self.plainTextContent = plainTextContent
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryColor = categoryColor
        self.typeRawValue = typeRawValue
        self.title = title
        self.body = body
        self.dictationText = dictationText
        self.answerText = answerText
        self.translation = translation
        self.note = note
        self.source = source
        self.tags = tags
        self.isPinned = isPinned
        self.needsReview = needsReview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "📄"
        coverStyle = try container.decodeIfPresent(String.self, forKey: .coverStyle) ?? "none"
        blocksJSON = try container.decodeIfPresent(String.self, forKey: .blocksJSON) ?? ""
        richTextData = try container.decodeIfPresent(String.self, forKey: .richTextData) ?? ""
        plainTextContent = try container.decodeIfPresent(String.self, forKey: .plainTextContent) ?? ""
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID) ?? ""
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName) ?? ""
        categoryColor = try container.decodeIfPresent(String.self, forKey: .categoryColor) ?? "gray"
        typeRawValue = try container.decodeIfPresent(String.self, forKey: .typeRawValue) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "가져온 학습 메모"
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        dictationText = try container.decodeIfPresent(String.self, forKey: .dictationText) ?? ""
        answerText = try container.decodeIfPresent(String.self, forKey: .answerText) ?? ""
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        tags = try container.decodeIfPresent(String.self, forKey: .tags) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        needsReview = try container.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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
    var quiz: VocaWordQuizArchive?

    init(
        id: UUID = UUID(), english: String, meaningKo: String = "", exampleEn: String = "",
        exampleKo: String = "", note: String = "", toeicTag: String = "", createdAt: Date = Date(),
        reviewCount: Int = 0, correctCount: Int = 0, wrongCount: Int = 0, masteryLevel: Int = 0,
        status: String = WordStatus.new.rawValue, nextReviewAt: Date = Date(), lastReviewedAt: Date? = nil,
        quiz: VocaWordQuizArchive? = nil
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
        self.quiz = quiz
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
        quiz = try container.decodeIfPresent(VocaWordQuizArchive.self, forKey: .quiz)
    }
}

struct AppDataImportPreview {
    let vocabularyDaysToCreate: Int
    let vocabularyDaysToUpdate: Int
    let wordsToCreate: Int
    let wordsToUpdate: Int
    let studyMemosToCreate: Int
    let studyMemosToUpdate: Int
    let categoriesToCreate: Int
    let categoriesToUpdate: Int

    var isEmpty: Bool {
        vocabularyDaysToCreate == 0 && vocabularyDaysToUpdate == 0 && wordsToCreate == 0 &&
        wordsToUpdate == 0 && studyMemosToCreate == 0 && studyMemosToUpdate == 0 &&
        categoriesToCreate == 0 && categoriesToUpdate == 0
    }

    var summary: String {
        guard !isEmpty else { return "반영할 변경 사항이 없습니다." }
        return [
            "단어 데이: 새로 만들기 \(vocabularyDaysToCreate)개, 업데이트 \(vocabularyDaysToUpdate)개",
            "단어: 새로 만들기 \(wordsToCreate)개, 업데이트 \(wordsToUpdate)개",
            "학습 메모: 새로 만들기 \(studyMemosToCreate)개, 업데이트 \(studyMemosToUpdate)개",
            "페이지 분류: 새로 만들기 \(categoriesToCreate)개, 업데이트 \(categoriesToUpdate)개"
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
    nonisolated static let currentSchemaVersion = 6

    static func archiveAll(
        vocabularyDays: [VocabularyDay],
        studyMemos: [StudyMemo],
        studyPageCategories: [StudyPageCategory]
    ) -> AppDataArchive {
        let context = vocabularyDays.first?.modelContext
        let progress = context
            .flatMap { try? $0.fetch(FetchDescriptor<StudyProgress>()) }
            .flatMap(StudyProgressStore.preferred)
        let logs = context
            .flatMap { try? $0.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.answeredAt)])) } ?? []
        return AppDataArchive(
            type: .allAppData,
            vocabularyDays: vocabularyDays.sortedByCreatedAt().map(Self.makeVocabularyDayArchive),
            studyMemos: studyMemos.sorted { $0.createdAt < $1.createdAt }.map(Self.makeStudyMemoArchive),
            studyPageCategories: studyPageCategories.sorted { $0.createdAt < $1.createdAt }.map(Self.makeCategoryArchive),
            studyProgress: progress.map { StudyProgressArchive(currentLearningDay: $0.currentLearningDay) },
            reviewLogs: logs.map {
                ReviewLogArchive(
                    id: $0.id, wordID: $0.wordID, sessionID: $0.sessionID, learningDay: $0.learningDay,
                    sessionKind: $0.sessionKind, mode: $0.mode, isCorrect: $0.isCorrect, outcomeDetail: $0.outcomeDetail,
                    stageBefore: $0.stageBefore, stageAfter: $0.stageAfter, answeredAt: $0.answeredAt
                )
            }
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
        guard archive.schemaVersion <= currentSchemaVersion else {
            throw AppDataBackupError.unsupportedVersion(archive.schemaVersion)
        }
        return archive
    }

    static func preview(
        _ archive: AppDataArchive,
        vocabularyDays: [VocabularyDay],
        studyMemos: [StudyMemo],
        studyPageCategories: [StudyPageCategory]
    ) -> AppDataImportPreview {
        let existingDayIDs = Set(vocabularyDays.map(\.id))
        let existingWordIDs = Set(vocabularyDays.flatMap { $0.wordList.map(\.id) })
        let existingMemoIDs = Set(studyMemos.map(\.id))
        let existingCategoryIDs = Set(studyPageCategories.map(\.id))
        let incomingWordIDs = archive.vocabularyDays.flatMap { $0.words.map(\.id) }

        return AppDataImportPreview(
            vocabularyDaysToCreate: archive.vocabularyDays.filter { !existingDayIDs.contains($0.id) }.count,
            vocabularyDaysToUpdate: archive.vocabularyDays.filter { existingDayIDs.contains($0.id) }.count,
            wordsToCreate: incomingWordIDs.filter { !existingWordIDs.contains($0) }.count,
            wordsToUpdate: incomingWordIDs.filter { existingWordIDs.contains($0) }.count,
            studyMemosToCreate: archive.studyMemos.filter { !existingMemoIDs.contains($0.id) }.count,
            studyMemosToUpdate: archive.studyMemos.filter { existingMemoIDs.contains($0.id) }.count,
            categoriesToCreate: archive.studyPageCategories.filter { !existingCategoryIDs.contains($0.id) }.count,
            categoriesToUpdate: archive.studyPageCategories.filter { existingCategoryIDs.contains($0.id) }.count
        )
    }

    static func applyUpsert(
        _ archive: AppDataArchive,
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        studyMemos: [StudyMemo],
        studyPageCategories: [StudyPageCategory]
    ) throws {
        var daysByID = Dictionary(uniqueKeysWithValues: vocabularyDays.map { ($0.id, $0) })
        var wordsByID = Dictionary(uniqueKeysWithValues: vocabularyDays.flatMap { day in
            day.wordList.map { ($0.id, $0) }
        })
        var memosByID = Dictionary(uniqueKeysWithValues: studyMemos.map { ($0.id, $0) })
        var categoriesByID = Dictionary(uniqueKeysWithValues: studyPageCategories.map { ($0.id, $0) })

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

        for categoryArchive in archive.studyPageCategories {
            let category = categoriesByID[categoryArchive.id] ?? {
                let newCategory = StudyPageCategory(id: categoryArchive.id, name: categoryArchive.name)
                context.insert(newCategory)
                categoriesByID[categoryArchive.id] = newCategory
                return newCategory
            }()
            apply(categoryArchive, to: category)
        }

        for memoArchive in archive.studyMemos {
            let memo = memosByID[memoArchive.id] ?? {
                let newMemo = StudyMemo(id: memoArchive.id)
                context.insert(newMemo)
                memosByID[memoArchive.id] = newMemo
                return newMemo
            }()
            apply(memoArchive, to: memo)
        }

        if let logArchives = archive.reviewLogs, !logArchives.isEmpty {
            let existingIDs = Set(((try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []).map(\.id))
            for log in logArchives where !existingIDs.contains(log.id) {
                context.insert(ReviewLog(
                    id: log.id, wordID: log.wordID, sessionID: log.sessionID, learningDay: log.learningDay,
                    sessionKind: log.sessionKind, mode: log.mode, isCorrect: log.isCorrect, outcomeDetail: log.outcomeDetail,
                    stageBefore: log.stageBefore, stageAfter: log.stageAfter, answeredAt: log.answeredAt
                ))
            }
        }

        if let progressArchive = archive.studyProgress {
            let progress = StudyProgressStore.fetchOrCreate(in: context)
            progress.currentLearningDay = max(progress.currentLearningDay, progressArchive.currentLearningDay)
        }
        try context.save()

        // 가져온 SRS 값이 기기에 남은 최고값에 막혀 되돌아가지 않도록 기준을 다시 잡는다.
        SRSProgressHighWaterStore.standard.reset()
        SRSProgressHighWaterStore.standard.record(Array(wordsByID.values))
    }

    static func deleteAll(
        in context: ModelContext,
        vocabularyDays: [VocabularyDay],
        studyMemos: [StudyMemo],
        studyPageCategories: [StudyPageCategory]
    ) throws {
        for day in vocabularyDays {
            context.delete(day)
        }
        for memo in studyMemos {
            context.delete(memo)
        }
        for category in studyPageCategories {
            context.delete(category)
        }
        for progress in (try? context.fetch(FetchDescriptor<StudyProgress>())) ?? [] {
            context.delete(progress)
        }
        for log in (try? context.fetch(FetchDescriptor<ReviewLog>())) ?? [] {
            context.delete(log)
        }
        try context.save()
        SRSProgressHighWaterStore.standard.reset()
        ExamSessionStore.standard.clear()
        StudyDayLedgerStore.standard.clear()
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
                    lastReviewedAt: word.lastReviewedAt,
                    quiz: VocaWordQuizArchive(
                        srsStage: word.srsStage,
                        srsNextLearningDay: word.srsNextLearningDay,
                        srsIdkCount: word.srsIdkCount,
                        pos: word.quizPos,
                        cefr: word.quizCefr,
                        meaningKo: word.quizMeaningKo,
                        disambiguationKo: word.quizDisambiguationKo,
                        formsJSON: word.quizFormsJSON,
                        termVariantsJSON: word.quizTermVariantsJSON,
                        example: word.quizExample,
                        exampleKo: word.quizExampleKo,
                        clozeSentence: word.quizClozeSentence,
                        clozeAnswer: word.quizClozeAnswer,
                        clozeForm: word.quizClozeForm,
                        clozeAcceptedJSON: word.quizClozeAcceptedJSON,
                        nearMissJSON: word.quizNearMissJSON,
                        enrichmentVersion: word.quizEnrichmentVersion,
                        enrichmentFingerprint: word.quizEnrichmentFingerprint
                    )
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

        if let quiz = archive.quiz {
            word.srsStage = max(0, min(quiz.srsStage, SRSEngine.maxStage))
            word.srsNextLearningDay = max(0, quiz.srsNextLearningDay)
            word.srsIdkCount = max(0, quiz.srsIdkCount)
            word.quizPos = quiz.pos
            word.quizCefr = quiz.cefr
            word.quizMeaningKo = quiz.meaningKo
            word.quizDisambiguationKo = quiz.disambiguationKo
            word.quizFormsJSON = quiz.formsJSON
            word.quizTermVariantsJSON = quiz.termVariantsJSON
            word.quizExample = quiz.example
            word.quizExampleKo = quiz.exampleKo
            word.quizClozeSentence = quiz.clozeSentence
            word.quizClozeAnswer = quiz.clozeAnswer
            word.quizClozeForm = quiz.clozeForm
            word.quizClozeAcceptedJSON = quiz.clozeAcceptedJSON
            word.quizNearMissJSON = quiz.nearMissJSON
            word.quizEnrichmentVersion = quiz.enrichmentVersion
            word.quizEnrichmentFingerprint = quiz.enrichmentFingerprint
        }
    }

    private static func makeStudyMemoArchive(_ memo: StudyMemo) -> StudyMemoArchive {
        StudyMemoArchive(
            id: memo.id,
            icon: memo.icon,
            coverStyle: memo.coverStyle,
            blocksJSON: memo.blocksJSON,
            richTextData: memo.richTextData,
            plainTextContent: memo.plainTextContent,
            categoryID: memo.categoryID,
            categoryName: memo.categoryName,
            categoryColor: memo.categoryColor,
            typeRawValue: memo.typeRawValue,
            title: memo.title,
            body: memo.body,
            dictationText: memo.dictationText,
            answerText: memo.answerText,
            translation: memo.translation,
            note: memo.note,
            source: memo.source,
            tags: memo.tags,
            isPinned: memo.isPinned,
            needsReview: memo.needsReview,
            createdAt: memo.createdAt,
            updatedAt: memo.updatedAt
        )
    }

    private static func apply(_ archive: StudyMemoArchive, to memo: StudyMemo) {
        memo.icon = archive.icon
        memo.coverStyle = archive.coverStyle
        memo.blocksJSON = archive.blocksJSON
        memo.richTextData = archive.richTextData
        memo.plainTextContent = archive.plainTextContent
        memo.categoryID = archive.categoryID
        memo.categoryName = archive.categoryName
        memo.categoryColor = archive.categoryColor
        memo.typeRawValue = archive.typeRawValue
        memo.title = archive.title
        memo.body = archive.body
        memo.dictationText = archive.dictationText
        memo.answerText = archive.answerText
        memo.translation = archive.translation
        memo.note = archive.note
        memo.source = archive.source
        memo.tags = archive.tags
        memo.isPinned = archive.isPinned
        memo.needsReview = archive.needsReview
        memo.createdAt = archive.createdAt
        memo.updatedAt = archive.updatedAt
        memo.migrateLegacyContentIfNeeded()
    }

    private static func makeCategoryArchive(_ category: StudyPageCategory) -> StudyPageCategoryArchive {
        StudyPageCategoryArchive(
            id: category.id,
            name: category.name,
            colorRawValue: category.colorRawValue,
            createdAt: category.createdAt
        )
    }

    private static func apply(_ archive: StudyPageCategoryArchive, to category: StudyPageCategory) {
        category.name = archive.name
        category.colorRawValue = archive.colorRawValue
        category.createdAt = archive.createdAt
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
