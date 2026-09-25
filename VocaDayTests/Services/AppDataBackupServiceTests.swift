import SwiftData
import XCTest
@testable import VocaDay

@MainActor
final class AppDataBackupServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: VocabularyDay.self, VocaWord.self, StudyMemo.self, StudyPageCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeMemoArchive(
        id: UUID = UUID(),
        title: String,
        categoryID: String = "",
        categoryName: String = "",
        categoryColor: String = "gray",
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> StudyMemoArchive {
        StudyMemoArchive(
            id: id,
            icon: "📄",
            coverStyle: "none",
            blocksJSON: "",
            richTextData: "",
            plainTextContent: "본문",
            categoryID: categoryID,
            categoryName: categoryName,
            categoryColor: categoryColor,
            typeRawValue: "",
            title: title,
            body: "",
            dictationText: "",
            answerText: "",
            translation: "",
            note: "",
            source: "",
            tags: "",
            isPinned: isPinned,
            needsReview: false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func testEncodeDecodeRoundTrip() throws {
        let dayID = UUID()
        let wordID = UUID()
        let memoID = UUID()
        let categoryID = UUID()

        let archive = AppDataArchive(
            type: .allAppData,
            vocabularyDays: [
                VocabularyDayArchive(
                    id: dayID,
                    title: "데이 1",
                    words: [VocaWordArchive(id: wordID, english: "accommodation", meaningKo: "숙박 시설")]
                )
            ],
            studyMemos: [makeMemoArchive(id: memoID, title: "메모 1")],
            studyPageCategories: [StudyPageCategoryArchive(id: categoryID, name: "문법", colorRawValue: "purple", createdAt: Date())]
        )

        let json = try AppDataBackupService.encode(archive)
        let decoded = try AppDataBackupService.decode(json)

        XCTAssertEqual(decoded.vocabularyDays.first?.id, dayID)
        XCTAssertEqual(decoded.vocabularyDays.first?.words.first?.english, "accommodation")
        XCTAssertEqual(decoded.studyMemos.first?.id, memoID)
        XCTAssertEqual(decoded.studyMemos.first?.title, "메모 1")
        XCTAssertEqual(decoded.studyPageCategories.first?.id, categoryID)
    }

    func testQuizAndSRSFieldsRoundTripAndOldBackupsKeepThem() throws {
        let context = try makeContext()
        let day = VocabularyDay(title: "Day 1")
        context.insert(day)
        let word = VocaWord(english: "abandon", meaningKo: "v. 버리다", day: day)
        word.srsStage = 4
        word.srsNextLearningDay = 12
        word.srsIdkCount = 2
        word.quizMeaningKo = "버리다"
        word.quizClozeSentence = "The crew had to <> the ship."
        word.quizEnrichmentVersion = 1
        context.insert(word)
        try context.save()

        let json = try AppDataBackupService.encode(AppDataBackupService.archiveVocabularyDay(day))
        let decoded = try AppDataBackupService.decode(json)
        XCTAssertEqual(decoded.schemaVersion, AppDataBackupService.currentSchemaVersion)

        let restoreContext = try makeContext()
        try AppDataBackupService.applyUpsert(decoded, in: restoreContext, vocabularyDays: [], studyMemos: [], studyPageCategories: [])
        let restored = try XCTUnwrap(restoreContext.fetch(FetchDescriptor<VocaWord>()).first)
        XCTAssertEqual(restored.srsCard, SRSCardState(stage: 4, nextLearningDay: 12, idkCount: 2))
        XCTAssertEqual(restored.quizMeaningKo, "버리다")
        XCTAssertEqual(restored.quizClozeSentence, "The crew had to <> the ship.")

        // schema 5 백업(quiz 없음)을 가져와도 기존 SRS 값은 그대로 둔다.
        var legacy = decoded
        legacy.vocabularyDays[0].words[0].quiz = nil
        legacy.vocabularyDays[0].words[0].meaningKo = "v. 버리다, 포기하다"
        try AppDataBackupService.applyUpsert(legacy, in: restoreContext, vocabularyDays: [restored.day!], studyMemos: [], studyPageCategories: [])
        XCTAssertEqual(restored.srsStage, 4)
        XCTAssertEqual(restored.meaningKo, "v. 버리다, 포기하다")
    }

    func testReviewLogsRoundTripInFullBackup() throws {
        let schema: [any PersistentModel.Type] = [VocabularyDay.self, VocaWord.self, StudyMemo.self, StudyPageCategory.self, StudyProgress.self, ReviewLog.self]
        let source = ModelContext(try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let day = VocabularyDay(title: "Day 1")
        source.insert(day)
        let word = VocaWord(english: "abandon", day: day)
        source.insert(word)
        let log = ReviewLog(
            wordID: word.id, sessionID: UUID(), learningDay: 3, sessionKind: "first", mode: "M2",
            isCorrect: true, stageBefore: 2, stageAfter: 3, answeredAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        source.insert(log)
        try source.save()

        let json = try AppDataBackupService.encode(
            AppDataBackupService.archiveAll(vocabularyDays: [day], studyMemos: [], studyPageCategories: [])
        )
        let archive = try AppDataBackupService.decode(json)
        XCTAssertEqual(archive.reviewLogs?.count, 1)

        let target = ModelContext(try ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        try AppDataBackupService.applyUpsert(archive, in: target, vocabularyDays: [], studyMemos: [], studyPageCategories: [])
        try AppDataBackupService.applyUpsert(archive, in: target, vocabularyDays: try target.fetch(FetchDescriptor<VocabularyDay>()), studyMemos: [], studyPageCategories: [])
        let restored = try target.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(restored.count, 1, "같은 백업을 두 번 가져와도 중복되지 않는다")
        XCTAssertEqual(restored.first?.id, log.id)
        XCTAssertEqual(restored.first?.mode, "M2")

        try AppDataBackupService.deleteAll(in: target, vocabularyDays: try target.fetch(FetchDescriptor<VocabularyDay>()), studyMemos: [], studyPageCategories: [])
        XCTAssertTrue(try target.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
    }

    func testDecodeThrowsForUnsupportedSchemaVersion() throws {
        let archive = AppDataArchive(schemaVersion: AppDataBackupService.currentSchemaVersion + 1, type: .allAppData)
        let json = try AppDataBackupService.encode(archive)

        XCTAssertThrowsError(try AppDataBackupService.decode(json)) { error in
            guard case AppDataBackupError.unsupportedVersion(let version) = error else {
                XCTFail("Expected unsupportedVersion, got \(error)")
                return
            }
            XCTAssertEqual(version, AppDataBackupService.currentSchemaVersion + 1)
        }
    }

    func testApplyUpsertCreatesNewEntities() throws {
        let context = try makeContext()
        let archive = AppDataArchive(
            type: .allAppData,
            vocabularyDays: [
                VocabularyDayArchive(title: "데이 1", words: [VocaWordArchive(english: "reimburse")])
            ],
            studyMemos: [makeMemoArchive(title: "새 메모")],
            studyPageCategories: [StudyPageCategoryArchive(id: UUID(), name: "표현", colorRawValue: "green", createdAt: Date())]
        )

        try AppDataBackupService.applyUpsert(archive, in: context, vocabularyDays: [], studyMemos: [], studyPageCategories: [])

        XCTAssertEqual(try context.fetch(FetchDescriptor<VocabularyDay>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<VocaWord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyMemo>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyPageCategory>()).count, 1)
    }

    func testApplyUpsertUpdatesExistingEntitiesWithoutDuplicating() throws {
        let context = try makeContext()
        let day = VocabularyDay(title: "원래 제목")
        context.insert(day)
        let word = VocaWord(english: "old", day: day)
        context.insert(word)
        day.appendWord(word)
        try context.save()

        let archive = AppDataArchive(
            type: .allAppData,
            vocabularyDays: [
                VocabularyDayArchive(
                    id: day.id,
                    title: "수정된 제목",
                    words: [VocaWordArchive(id: word.id, english: "updated")]
                )
            ]
        )

        try AppDataBackupService.applyUpsert(archive, in: context, vocabularyDays: [day], studyMemos: [], studyPageCategories: [])

        let days = try context.fetch(FetchDescriptor<VocabularyDay>())
        let words = try context.fetch(FetchDescriptor<VocaWord>())
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(days.first?.title, "수정된 제목")
        XCTAssertEqual(words.first?.english, "updated")
    }

    func testApplyUpsertReparentsWordToDifferentDay() throws {
        let context = try makeContext()
        let originalDay = VocabularyDay(title: "원래 데이")
        let targetDay = VocabularyDay(title: "옮길 데이")
        context.insert(originalDay)
        context.insert(targetDay)
        let word = VocaWord(english: "itinerary", day: originalDay)
        context.insert(word)
        originalDay.appendWord(word)
        try context.save()

        let archive = AppDataArchive(
            type: .allAppData,
            vocabularyDays: [
                VocabularyDayArchive(id: originalDay.id, title: originalDay.title, words: []),
                VocabularyDayArchive(id: targetDay.id, title: targetDay.title, words: [VocaWordArchive(id: word.id, english: "itinerary")])
            ]
        )

        try AppDataBackupService.applyUpsert(
            archive,
            in: context,
            vocabularyDays: [originalDay, targetDay],
            studyMemos: [],
            studyPageCategories: []
        )

        XCTAssertEqual(word.day?.id, targetDay.id)
        XCTAssertFalse(originalDay.wordList.contains { $0.id == word.id })
        XCTAssertTrue(targetDay.wordList.contains { $0.id == word.id })
    }

    func testDeleteAllRemovesEveryEntity() throws {
        let context = try makeContext()
        let day = VocabularyDay(title: "데이")
        context.insert(day)
        let word = VocaWord(english: "mandatory", day: day)
        context.insert(word)
        day.appendWord(word)
        let memo = StudyMemo(title: "메모")
        context.insert(memo)
        let category = StudyPageCategory(name: "분류")
        context.insert(category)
        try context.save()

        try AppDataBackupService.deleteAll(
            in: context,
            vocabularyDays: [day],
            studyMemos: [memo],
            studyPageCategories: [category]
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<VocabularyDay>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VocaWord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyMemo>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyPageCategory>()).isEmpty)
    }

    func testPreviewCountsCreateAndUpdate() throws {
        let existingDay = VocabularyDay(title: "기존 데이")
        let newDayID = UUID()

        let archive = AppDataArchive(
            type: .allAppData,
            vocabularyDays: [
                VocabularyDayArchive(id: existingDay.id, title: "기존 데이 업데이트", words: []),
                VocabularyDayArchive(id: newDayID, title: "새 데이", words: [])
            ]
        )

        let preview = AppDataBackupService.preview(
            archive,
            vocabularyDays: [existingDay],
            studyMemos: [],
            studyPageCategories: []
        )

        XCTAssertEqual(preview.vocabularyDaysToCreate, 1)
        XCTAssertEqual(preview.vocabularyDaysToUpdate, 1)
        XCTAssertFalse(preview.isEmpty)
    }
}
