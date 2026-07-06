import SwiftUI

struct DayCardView: View {
    let day: VocabularyDay
    let isSelected: Bool

    private var dueCount: Int {
        day.words.filter { ReviewScheduler.isDue($0) }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Created \(day.createdAt, format: .dateTime.month().day().year())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            metric(title: "Words", value: day.words.count)
            metric(title: "Due", value: dueCount)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .calmCard()
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
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
        .frame(minWidth: 54, alignment: .trailing)
    }
}
