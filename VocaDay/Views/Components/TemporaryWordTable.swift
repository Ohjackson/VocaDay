import SwiftUI

struct TemporaryWordTable: View {
    @Binding var words: [VocaWordJSON]
    @Binding var selectedWordID: UUID?
    var emptyTitle: String

    private struct Column {
        let title: String
        let width: CGFloat
    }

    private let columns: [Column] = [
        Column(title: "#", width: 56),
        Column(title: "영단어", width: 180),
        Column(title: "한국어 뜻", width: 220),
        Column(title: "메모", width: 180),
        Column(title: "TOEIC 태그", width: 150)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("저장 전 확인")
                        .font(.headline)
                    Text("셀을 눌러 내용을 수정하세요. 행을 선택하면 아래에서 삭제할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("\(words.count)개")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if words.isEmpty {
                EmptyStateView(
                    title: emptyTitle,
                    systemImage: "square.and.pencil"
                )
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        tableRow(
                            values: columns.map(\.title),
                            isHeader: true
                        )

                        Divider()

                        ForEach(Array(words.indices), id: \.self) { index in
                            editableWordRow(index: index, word: $words[index])
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

    private func editableWordRow(index: Int, word: Binding<VocaWordJSON>) -> some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.body.monospacedDigit())
                .frame(width: columns[0].width, alignment: .center)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

            editableCell("영단어", text: word.english, columnIndex: 1)
            editableCell("한국어 뜻", text: word.meaningKo, columnIndex: 2)
            editableCell("메모", text: word.note, columnIndex: 3)
            editableCell("TOEIC 태그", text: word.toeicTag, columnIndex: 4)
        }
        .background(rowBackground(isHeader: false, isSelected: selectedWordID == word.wrappedValue.id))
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedWordID = word.wrappedValue.id
            }
        )
    }

    private func editableCell(_ placeholder: String, text: Binding<String>, columnIndex: Int) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1)
            .frame(width: columns[columnIndex].width, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
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
}
