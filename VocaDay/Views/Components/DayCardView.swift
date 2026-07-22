import SwiftUI

struct DayCardView: View {
    let day: VocabularyDay
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text("Created")
                    Text(day.createdAt, format: .dateTime.month().day().year())
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("Last reviewed")
                    if let lastReviewedAt = day.lastReviewedAt {
                        Text(lastReviewedAt, format: .dateTime.month().day().year())
                    } else {
                        Text("-")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 18) {
                metric(title: "Words", value: day.wordList.count)
                metric(title: "Reviews", value: day.reviewSessionCount)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116)
        .calmCard()
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func metric(title: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 54, alignment: .trailing)
    }
}
