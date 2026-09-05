import SwiftUI

struct StudyPageRowPresentation: Equatable, Sendable {
    let title: String
    let isPinned: Bool
    let categoryName: String
    let categoryColorRawValue: String
    let previewText: String
    let updatedAt: Date

    init(
        title: String,
        isPinned: Bool,
        categoryName: String,
        categoryColorRawValue: String,
        previewText: String,
        updatedAt: Date
    ) {
        self.title = title
        self.isPinned = isPinned
        self.categoryName = categoryName
        self.categoryColorRawValue = categoryColorRawValue
        self.previewText = previewText
        self.updatedAt = updatedAt
    }

    init(memo: StudyMemo) {
        self.init(
            title: memo.title,
            isPinned: memo.isPinned,
            categoryName: memo.categoryName,
            categoryColorRawValue: memo.categoryColor,
            previewText: StudyMarkdownMigration.preview(from: memo.previewText),
            updatedAt: memo.updatedAt
        )
    }
}

struct StudyPageListRow: View {
    let presentation: StudyPageRowPresentation
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(presentation.title.isEmpty ? "제목 없음" : presentation.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if presentation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !presentation.categoryName.isEmpty {
                        StudyCategoryBadge(
                            name: presentation.categoryName,
                            colorRawValue: presentation.categoryColorRawValue
                        )
                    }
                }

                Text(presentation.previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(presentation.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(isHovering ? StudyPageStyle.hover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
