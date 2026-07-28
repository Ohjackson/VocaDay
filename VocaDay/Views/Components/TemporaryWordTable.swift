import SwiftUI

struct TemporaryWordTable: View {
    let words: [VocaWordJSON]
    @Binding var selectedWordID: UUID?

    private struct Column {
        let title: String
        let width: CGFloat
    }

    private let columns: [Column] = [
        Column(title: "#", width: 56),
        Column(title: "영단어", width: 180),
        Column(title: "한국어 뜻", width: 220),
        Column(title: "메모", width: 180),
        Column(title: "TOEIC 태그", width: 150),
        Column(title: "오답 횟수", width: 130)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("임시 단어")
                    .font(.headline)

                Spacer()

                Text("\(words.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if words.isEmpty {
                EmptyStateView(
                    title: "아직 단어가 없습니다. 영단어를 입력해 시작하세요.",
                    systemImage: "square.and.pencil"
                )
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        tableRow(
                            values: columns.map(\.title),
                            isHeader: true
                        )

                        Divider()

                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            tableRow(
                                values: [
                                    "\(index + 1)",
                                    word.english,
                                    display(word.meaningKo),
                                    display(word.note),
                                    display(word.toeicTag),
                                    "0"
                                ],
                                isHeader: false,
                                isSelected: selectedWordID == word.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedWordID = word.id
                            }
                            Divider()
                        }
                    }
                    .frame(minWidth: columns.reduce(0) { $0 + $1.width }, alignment: .leading)
                }
            }
        }
        .padding(18)
        .calmCard()
    }

    private func tableRow(values: [String], isHeader: Bool, isSelected: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(isHeader ? .subheadline.weight(.semibold) : .body)
                    .foregroundStyle(isHeader ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(width: columns[index].width, alignment: index == 0 ? .center : .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
            }
        }
        .background(rowBackground(isHeader: isHeader, isSelected: isSelected))
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
