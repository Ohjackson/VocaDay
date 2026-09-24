import Combine
import Foundation
import SwiftData

@MainActor
final class StudyMemosListViewModel: ObservableObject {
    @Published var errorAlert: VocaAlert?

    @discardableResult
    func togglePin(_ memo: StudyMemo, in context: ModelContext) -> Bool {
        memo.isPinned.toggle()
        memo.updatedAt = Date()
        return save(in: context)
    }

    func createPage(in context: ModelContext) -> StudyMemo? {
        let memo = StudyMemo(title: "", icon: "", plainTextContent: "")
        context.insert(memo)
        guard save(in: context) else { return nil }
        return memo
    }

    func duplicate(_ source: StudyMemo, in context: ModelContext) -> StudyMemo? {
        let copy = StudyMemo(
            title: source.title.isEmpty ? "페이지 복사본" : "\(source.title) 복사본",
            icon: "",
            blocks: source.blocks,
            plainTextContent: StudyMarkdownMigration.markdown(for: source),
            categoryID: source.categoryID,
            categoryName: source.categoryName,
            categoryColor: source.categoryColor,
            isPinned: false
        )
        context.insert(copy)
        guard save(in: context) else { return nil }
        return copy
    }

    func migrateLegacyPages(_ memos: [StudyMemo], in context: ModelContext) {
        var changed = false
        for memo in memos {
            if memo.migrateLegacyContentIfNeeded() { changed = true }
            if memo.plainTextContent.isEmpty,
               !memo.blocksJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                memo.plainTextContent = StudyMarkdownMigration.markdown(for: memo)
                memo.richTextData = ""
                changed = true
            }
        }
        if changed { save(in: context) }
    }

    func repairLegacyData(_ memos: [StudyMemo], in context: ModelContext) {
        do {
            try StudyMemoDemoSeeder.repair(existingMemos: memos, in: context)
        } catch {
            errorAlert = .saveFailure(error)
        }
    }

    @discardableResult
    func deletePendingMemo(_ memo: StudyMemo, in context: ModelContext) -> Bool {
        context.delete(memo)
        return save(in: context)
    }

    @discardableResult
    private func save(in context: ModelContext) -> Bool {
        if let error = context.saveReportingError() {
            errorAlert = .saveFailure(error)
            return false
        }
        return true
    }
}
