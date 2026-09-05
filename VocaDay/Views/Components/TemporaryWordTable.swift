import SwiftUI

struct TemporaryWordTable: View {
    @Binding var words: [VocaWordJSON]
    @Binding var selectedWordID: UUID?
    var emptyTitle: String

    @State private var expandedWordIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("저장 전 목록")
                        .font(.headline)
                    Text("내용을 눌러 바로 수정할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(words.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
            }

            if words.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "text.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(emptyTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
                .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(words.indices), id: \.self) { index in
                        editableWordCard(index: index, word: $words[index])
                    }
                }
            }
        }
        .padding(16)
        .calmCard()
    }

    private func editableWordCard(index: Int, word: Binding<VocaWordJSON>) -> some View {
        let wordID = word.wrappedValue.id
        let isExpanded = expandedWordIDs.contains(wordID)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.1), in: Circle())

                TextField("영단어", text: word.english)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .autocorrectionDisabled()

                Button(role: .destructive) {
                    removeWord(at: index)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(word.wrappedValue.english) 삭제")
            }

            if word.wrappedValue.meaningKo == "(번역 중...)" {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("한국어 뜻을 불러오는 중…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 34)
            } else {
                compactTextField("한국어 뜻", text: word.meaningKo)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedWordIDs.remove(wordID)
                    } else {
                        expandedWordIDs.insert(wordID)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "세부 정보 접기" : "예문 · 메모 · 태그")
                        .font(.caption.weight(.semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                editableField("영어 예문", text: word.exampleEn, placeholder: "영어 예문 입력")
                editableField("예문 번역", text: word.exampleKo, placeholder: "한국어 번역 입력")
                editableField("메모", text: word.note, placeholder: "암기 메모 입력")
                editableField("TOEIC 태그", text: word.toeicTag, placeholder: "예: 동사, Part 5")
            }
        }
        .padding(14)
        .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.1))
        }
        .onTapGesture { selectedWordID = wordID }
    }

    private func compactTextField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...3)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func editableField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            compactTextField(placeholder, text: text)
        }
    }

    private func removeWord(at index: Int) {
        guard words.indices.contains(index) else { return }
        let removedID = words[index].id
        words.remove(at: index)
        expandedWordIDs.remove(removedID)
        if selectedWordID == removedID {
            selectedWordID = words.indices.contains(index) ? words[index].id : words.last?.id
        }
    }
}
