import SwiftUI

struct WordDataTable: View {
    let title: String
    let words: [VocaWord]
    var hideKoreanMeaning = false
    var allowsSelection = false
    var showsTitle = true
    var showsWordDetails = false
    var emptyTitle: LocalizedStringKey = "No saved words in this Day."
    @Binding var selectedWordIDs: Set<UUID>

    var body: some View {
        fullWidthTable
    }

    private var fullWidthTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    Text("\(words.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if words.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    systemImage: "text.page"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else {
                GeometryReader { proxy in
                    let widths = columnWidths(totalWidth: proxy.size.width)

                    VStack(spacing: 0) {
                        proportionalRow(
                            values: ["#", "English", "Korean Meaning"],
                            widths: widths,
                            isHeader: true
                        )

                        Divider()

                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            wordRow(index: index, word: word, widths: widths)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard allowsSelection else { return }
                                if selectedWordIDs.contains(word.id) {
                                    selectedWordIDs.remove(word.id)
                                } else {
                                    selectedWordIDs.insert(word.id)
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(height: tableHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.cardBackground)
    }

    private func columnWidths(totalWidth: CGFloat) -> [CGFloat] {
        [
            totalWidth * 0.10,
            totalWidth * 0.45,
            totalWidth * 0.45
        ]
    }

    private var tableHeight: CGFloat {
        let headerHeight: CGFloat = 45
        let rowHeight: CGFloat = showsWordDetails ? 134 : 45
        return headerHeight + (CGFloat(words.count) * rowHeight)
    }

    private func wordRow(index: Int, word: VocaWord, widths: [CGFloat]) -> some View {
        VStack(spacing: 0) {
            proportionalRow(
                values: [
                    "\(index + 1)",
                    word.english,
                    hideKoreanMeaning ? "••••" : display(word.meaningKo)
                ],
                count: word.wrongCount,
                widths: widths,
                isHeader: false,
                isSelected: selectedWordIDs.contains(word.id)
            )

            if showsWordDetails {
                wordDetailLines(for: word)
            }
        }
        .background(rowBackground(isHeader: false, isSelected: selectedWordIDs.contains(word.id)))
    }

    private func proportionalRow(values: [String], count: Int? = nil, widths: [CGFloat], isHeader: Bool, isSelected: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                cell(value: value, count: index == 0 ? count : nil, index: index, isHeader: isHeader)
                    .frame(width: widths[index], height: 44, alignment: index == 0 ? .center : .leading)
                    .padding(.horizontal, index == 0 ? 2 : 6)
                    .overlay(alignment: .trailing) {
                        if index < values.count - 1 {
                            Rectangle()
                                .fill(AppTheme.softStroke)
                                .frame(width: 0.5)
                        }
                    }
            }
        }
        .background(rowBackground(isHeader: isHeader, isSelected: isSelected))
    }

    private func wordDetailLines(for word: VocaWord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            detailLine(label: "Example", value: word.exampleEn)
            detailLine(label: "Korean", value: word.exampleKo)
            detailLine(label: "Note", value: word.note)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color.secondary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.32))
                .frame(height: 1)
        }
    }

    private func detailLine(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(display(value))
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cell(value: String, count: Int?, index: Int, isHeader: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if isHeader {
                    Text(LocalizedStringKey(value))
                } else {
                    Text(value)
                }
            }
            .font(isHeader ? .caption.weight(.semibold) : compactFont(for: index, value: value))
            .minimumScaleFactor(0.45)
            .foregroundStyle(isHeader ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: index == 0 ? .center : .leading)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
                    .padding(.bottom, 4)
            }
        }
    }

    private func compactFont(for index: Int, value: String) -> Font {
        if value.count > 18 {
            return .caption
        }

        return .subheadline
    }

    private func rowBackground(isHeader: Bool, isSelected: Bool) -> Color {
        if isHeader {
            return Color.secondary.opacity(0.06)
        }

        return isSelected ? Color.accentColor.opacity(0.12) : Color.clear
    }

    private func display(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value
    }
}
