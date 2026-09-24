import SwiftData
import XCTest
@testable import VocaDay

@MainActor
final class StudyMemosListViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: StudyMemo.self, StudyPageCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testCreatePageInsertsAndSavesAnEmptyMemo() throws {
        let context = try makeContext()
        let viewModel = StudyMemosListViewModel()

        let memo = viewModel.createPage(in: context)

        XCTAssertNotNil(memo)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyMemo>()).count, 1)
        XCTAssertNil(viewModel.errorAlert)
    }

    func testDuplicateCopiesContentAndCategory() throws {
        let context = try makeContext()
        let viewModel = StudyMemosListViewModel()
        let source = StudyMemo(
            title: "원본",
            categoryID: "cat-1",
            categoryName: "문법",
            categoryColor: "purple"
        )
        context.insert(source)
        try context.save()

        let copy = try XCTUnwrap(viewModel.duplicate(source, in: context))

        XCTAssertEqual(copy.title, "원본 복사본")
        XCTAssertEqual(copy.categoryName, "문법")
        XCTAssertFalse(copy.isPinned)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyMemo>()).count, 2)
    }

    func testDeletePendingMemoRemovesIt() throws {
        let context = try makeContext()
        let viewModel = StudyMemosListViewModel()
        let memo = StudyMemo(title: "삭제 대상")
        context.insert(memo)
        try context.save()

        let didDelete = viewModel.deletePendingMemo(memo, in: context)

        XCTAssertTrue(didDelete)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StudyMemo>()).isEmpty)
    }

    func testMigrateLegacyPagesConvertsLegacyContentOnly() throws {
        let context = try makeContext()
        let viewModel = StudyMemosListViewModel()
        let legacyMemo = StudyMemo(title: "레거시")
        legacyMemo.typeRawValue = "grammar"
        legacyMemo.body = "핵심 설명"
        legacyMemo.blocksJSON = ""
        context.insert(legacyMemo)
        try context.save()
        XCTAssertTrue(legacyMemo.blocksJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        viewModel.migrateLegacyPages([legacyMemo], in: context)

        XCTAssertFalse(legacyMemo.blocksJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testTogglePinFlipsStateAndSaves() throws {
        let context = try makeContext()
        let viewModel = StudyMemosListViewModel()
        let memo = StudyMemo(title: "고정 테스트")
        context.insert(memo)
        try context.save()

        let didSave = viewModel.togglePin(memo, in: context)

        XCTAssertTrue(didSave)
        XCTAssertTrue(memo.isPinned)
    }
}
