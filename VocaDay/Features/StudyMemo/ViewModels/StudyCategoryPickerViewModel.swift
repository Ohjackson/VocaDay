import Combine
import Foundation
import SwiftData

@MainActor
final class StudyCategoryPickerViewModel: ObservableObject {
    @Published var errorAlert: VocaAlert?

    func createAndAssign(
        name: String,
        color: StudyCategoryColor,
        existingCategories: [StudyPageCategory],
        to memo: StudyMemo,
        in context: ModelContext
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        if let existing = existingCategories.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            return assign(existing, to: memo, in: context)
        }

        let category = StudyPageCategory(name: trimmedName, colorRawValue: color.rawValue)
        context.insert(category)
        return assign(category, to: memo, in: context)
    }

    @discardableResult
    func assign(_ category: StudyPageCategory?, to memo: StudyMemo, in context: ModelContext) -> Bool {
        memo.categoryID = category?.id.uuidString ?? ""
        memo.categoryName = category?.name ?? ""
        memo.categoryColor = category?.colorRawValue ?? StudyCategoryColor.gray.rawValue
        memo.updatedAt = Date()
        return save(in: context)
    }

    func deleteCategories(_ categoriesToDelete: [StudyPageCategory], affecting memos: [StudyMemo], in context: ModelContext) {
        let idsToDelete = Set(categoriesToDelete.map { $0.id.uuidString })
        for affectedMemo in memos where idsToDelete.contains(affectedMemo.categoryID) {
            affectedMemo.categoryID = ""
            affectedMemo.categoryName = ""
            affectedMemo.categoryColor = StudyCategoryColor.gray.rawValue
            affectedMemo.updatedAt = Date()
        }
        for category in categoriesToDelete {
            context.delete(category)
        }
        save(in: context)
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
