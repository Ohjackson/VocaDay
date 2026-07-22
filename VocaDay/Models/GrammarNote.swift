import Foundation
import SwiftData

@Model
final class GrammarNote {
    var id: UUID = UUID()
    var title: String = ""
    var markdown: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFavorite: Bool = false
    var isCompleted: Bool = false

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

    var previewText: String {
        markdown
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "|", with: " ")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty } ?? String(localized: "No content yet.")
    }
}
