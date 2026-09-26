import SwiftUI

struct DayCardPresentation: Equatable, Sendable {
    /// 이 단계 이상이면 '익힘'으로 센다. `SRSEngine.baseGaps` 기준 다음 출제까지 4학습일 이상 남은 단어.
    static let learnedStage = 5

    let title: String
    let createdAt: Date
    /// 카드·시험 중 이 데이 단어를 마지막으로 푼 때.
    let lastStudiedAt: Date?
    let wordCount: Int
    let learnedCount: Int
    let dueReviewCount: Int?

    init(
        title: String,
        createdAt: Date,
        lastStudiedAt: Date?,
        wordCount: Int,
        learnedCount: Int,
        dueReviewCount: Int? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.lastStudiedAt = lastStudiedAt
        self.wordCount = wordCount
        self.learnedCount = learnedCount
        self.dueReviewCount = dueReviewCount
    }

    init(day: VocabularyDay, dueReviewCount: Int? = nil) {
        let words = day.wordList
        self.init(
            title: day.title,
            createdAt: day.createdAt,
            // 단어별 기록은 `SRSStudyService`가 카드·시험 모두에서 남긴다. 예전 데이 기록도 함께 본다.
            lastStudiedAt: (words.compactMap(\.lastReviewedAt) + [day.lastReviewedAt].compactMap { $0 }).max(),
            wordCount: words.count,
            learnedCount: words.filter { $0.srsStage >= Self.learnedStage }.count,
            dueReviewCount: dueReviewCount
        )
    }
}

struct DayCardView: View {
    let presentation: DayCardPresentation
    let isSelected: Bool

    init(day: VocabularyDay, isSelected: Bool, dueReviewCount: Int? = nil) {
        presentation = DayCardPresentation(day: day, dueReviewCount: dueReviewCount)
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
                Text("마지막 학습")
                if let lastStudiedAt = presentation.lastStudiedAt {
                    Text(lastStudiedAt, format: .dateTime.month().day().year())
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
            if let dueReviewCount = presentation.dueReviewCount {
                metric(title: "오늘", value: dueReviewCount, emphasizesValue: dueReviewCount > 0)
            }
            metric(title: "단어", value: presentation.wordCount)
            metric(title: "익힘", value: presentation.learnedCount)
        }
    }

    private func metric(title: String, value: Int, emphasizesValue: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(emphasizesValue ? Color.accentColor : Color.primary)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 44, alignment: .trailing)
    }
}
