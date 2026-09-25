import SwiftUI

extension StageBucket {
    var color: Color {
        switch self {
        case .new: .gray
        case .learning: .orange
        case .familiar: .blue
        case .longTerm: .green
        }
    }
}

extension ExamItemKind {
    var displayName: String {
        switch self {
        case .newWord: "새 단어"
        case .match: "짝 맞추기"
        case .choice: "빈칸 고르기"
        case .clozeTyping: "빈칸 쓰기"
        case .koToEn: "한→영 쓰기"
        case .meaningChoice: "뜻 고르기"
        case .clozeChoiceWithoutTranslation: "빈칸 고르기(번역 없이)"
        case .letterTiles: "글자 조각 맞추기"
        case .dictation: "듣고 쓰기"
        case .flashcard: "복습 카드"
        }
    }
}

/// 제목이 있는 통계 카드.
struct StatsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calmCard()
    }
}

/// 숫자 하나를 크게 보여 주는 타일.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(12)
        .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct StageBadge: View {
    let stage: Int

    var body: some View {
        let bucket = StageBucket.of(stage: stage)
        Text("\(stage)")
            .font(.caption.weight(.bold).monospacedDigit())
            .frame(minWidth: 26, minHeight: 22)
            .foregroundStyle(bucket.color)
            .background(bucket.color.opacity(0.15), in: Capsule())
            .accessibilityLabel("단계 \(stage), \(bucket.title)")
    }
}

struct BucketLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(StageBucket.allCases) { bucket in
                HStack(spacing: 4) {
                    Circle().fill(bucket.color).frame(width: 8, height: 8)
                    Text(bucket.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

func percentText(_ value: Double?) -> String {
    guard let value else { return "–" }
    return "\(Int((value * 100).rounded()))%"
}

func learningDayText(_ offset: Int) -> String {
    offset <= 0 ? "오늘" : "\(offset)학습일 뒤"
}
