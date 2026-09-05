import SwiftUI

struct DayCardPresentation: Equatable, Sendable {
    let title: String
    let createdAt: Date
    let lastReviewedAt: Date?
    let wordCount: Int
    let reviewSessionCount: Int

    init(
        title: String,
        createdAt: Date,
        lastReviewedAt: Date?,
        wordCount: Int,
        reviewSessionCount: Int
    ) {
        self.title = title
        self.createdAt = createdAt
        self.lastReviewedAt = lastReviewedAt
        self.wordCount = wordCount
        self.reviewSessionCount = reviewSessionCount
    }

    init(day: VocabularyDay) {
        self.init(
            title: day.title,
            createdAt: day.createdAt,
            lastReviewedAt: day.lastReviewedAt,
            wordCount: day.wordList.count,
            reviewSessionCount: day.reviewSessionCount
        )
    }
}

struct DayCardView: View {
    let presentation: DayCardPresentation
    let isSelected: Bool

    init(day: VocabularyDay, isSelected: Bool) {
        presentation = DayCardPresentation(day: day)
        self.isSelected = isSelected
    }

    init(presentation: DayCardPresentation, isSelected: Bool = false) {
        self.presentation = presentation
        self.isSelected = isSelected
    }

    var body: some View {
        adaptiveContent
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116)
            .calmCard()
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        #if os(macOS)
        regularContent
        #else
        ViewThatFits(in: .horizontal) {
            regularContent
                .frame(minWidth: 330)
            compactContent
        }
        #endif
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            metadata
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            metrics
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(alignment: .bottom, spacing: 8) {
                dateMetadata
                    .frame(maxWidth: .infinity, alignment: .leading)

                metrics
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            dateMetadata
        }
    }

    private var dateMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("생성일")
                Text(presentation.createdAt, format: .dateTime.month().day().year())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 4) {
                Text("마지막 복습")
                if let lastReviewedAt = presentation.lastReviewedAt {
                    Text(lastReviewedAt, format: .dateTime.month().day().year())
                } else {
                    Text("-")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric(title: "단어", value: presentation.wordCount)
            metric(title: "복습", value: presentation.reviewSessionCount)
        }
    }

    private func metric(title: String, value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44, alignment: .trailing)
    }
}
