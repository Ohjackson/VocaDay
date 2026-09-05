import SwiftData
import SwiftUI
import XCTest
@testable import VocaDay

@MainActor
final class StudyMemoEditorTests: XCTestCase {
    func testMarkdownShortcutsStripTheirPrefix() throws {
        let heading = try XCTUnwrap(StudyMarkdownBlockShortcut.conversion(for: AttributedString("## 제목")))
        XCTAssertEqual(heading.kind, .heading2)
        XCTAssertEqual(String(heading.remainder.characters), "제목")

        let bullet = try XCTUnwrap(StudyMarkdownBlockShortcut.conversion(for: AttributedString("- 항목")))
        XCTAssertEqual(bullet.kind, .bulletedList)
        XCTAssertEqual(String(bullet.remainder.characters), "항목")

        let number = try XCTUnwrap(StudyMarkdownBlockShortcut.conversion(for: AttributedString("1. 항목")))
        XCTAssertEqual(number.kind, .numberedList)
        XCTAssertEqual(String(number.remainder.characters), "항목")
    }

    func testDeletionSentinelNeverLeaksIntoLogicalText() {
        let editorText = StudyEditorBuffer.displayText(AttributedString(), for: .bulletedList)
        XCTAssertTrue(StudyEditorBuffer.isOnlyDeletionSentinel(editorText))
        XCTAssertEqual(String(StudyEditorBuffer.logicalText(editorText).characters), "")
    }

    func testMarkdownHighlightAppliesOnlyToMarkedRange() throws {
        let blocks = StudyNotionCodec.blocks(from: "앞 <mark>강조</mark> 뒤")
        let block = try XCTUnwrap(blocks.first)
        let attributed = StudyNotionCodec.attributedText(for: block)
        XCTAssertEqual(String(attributed.characters), "앞 강조 뒤")

        let highlighted = attributed.runs.compactMap { run -> String? in
            guard run.backgroundColor != nil else { return nil }
            return String(attributed[run.range].characters)
        }
        XCTAssertEqual(highlighted, ["강조"])
    }

    func testMarkdownPageRoundTripKeepsTitleAndCategory() {
        let source = StudyMarkdownCodec.exportPage(
            title: "테스트 페이지",
            categoryName: "문법",
            body: "## 소제목\n\n본문"
        )
        let imported = StudyMarkdownCodec.importPage(source)
        XCTAssertEqual(imported.title, "테스트 페이지")
        XCTAssertEqual(imported.categoryName, "문법")
        XCTAssertEqual(imported.body, "## 소제목\n\n본문\n")
    }

    func testDuplicateDemoMemosAndCategoriesAreConsolidated() throws {
        let container = try ModelContainer(
            for: StudyMemo.self,
            StudyPageCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let firstCategory = StudyPageCategory(name: "문법", colorRawValue: "purple")
        let duplicateCategory = StudyPageCategory(name: " 문법 ", colorRawValue: "red")
        context.insert(firstCategory)
        context.insert(duplicateCategory)

        let title = "예시 · 현재완료와 과거시제"
        let older = StudyMemo(
            title: title,
            categoryID: firstCategory.id.uuidString,
            categoryName: firstCategory.name,
            categoryColor: firstCategory.colorRawValue,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let newer = StudyMemo(
            title: title,
            categoryID: duplicateCategory.id.uuidString,
            categoryName: duplicateCategory.name,
            categoryColor: duplicateCategory.colorRawValue,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        try StudyMemoDemoSeeder.repair(existingMemos: [older, newer], in: context)

        let categories = try context.fetch(FetchDescriptor<StudyPageCategory>())
        let memos = try context.fetch(FetchDescriptor<StudyMemo>())
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(memos.count, 1)
        XCTAssertEqual(memos.first?.id, newer.id)
        XCTAssertEqual(memos.first?.categoryID, categories.first?.id.uuidString)
    }
}
