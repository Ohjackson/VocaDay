import SwiftUI

struct TemporaryWordTable: View {
    @Binding var words: [VocaWordJSON]
    @Binding var selectedWordID: UUID?
    var emptyTitle: String

    @State private var editingWordID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("저장 전 목록")
                        .font(.headline)
                    Text("영단어를 눌러 뜻·예문·메모를 입력하세요.")
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
                        wordCard(index: index, word: words[index])
                    }
                }
            }
        }
        .padding(16)
        .calmCard()
        .sheet(isPresented: isShowingEditor) {
            if let index = words.firstIndex(where: { $0.id == editingWordID }) {
                EditDraftWordSheet(word: $words[index])
            }
        }
    }

    private var isShowingEditor: Binding<Bool> {
        Binding(
            get: { editingWordID != nil },
            set: { newValue in
                if !newValue { editingWordID = nil }
            }
        )
    }

    private func wordCard(index: Int, word: VocaWordJSON) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.1), in: Circle())

            Button {
                selectedWordID = word.id
                editingWordID = word.id
            } label: {
                Text(word.english.isEmpty ? "영단어 입력" : word.english)
                    .font(.headline)
                    .foregroundStyle(word.english.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(word.english) 편집")
            .accessibilityHint("뜻, 예문, 메모를 입력합니다.")

            Button(role: .destructive) {
                removeWord(at: index)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(word.english) 삭제")
        }
        .padding(14)
        .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.1))
        }
    }

    private func removeWord(at index: Int) {
        guard words.indices.contains(index) else { return }
        let removedID = words[index].id
        words.remove(at: index)
        if editingWordID == removedID {
            editingWordID = nil
        }
        if selectedWordID == removedID {
            selectedWordID = words.indices.contains(index) ? words[index].id : words.last?.id
        }
    }
}

private struct EditDraftWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var word: VocaWordJSON

    var body: some View {
        NavigationStack {
            Form {
                Section("단어") {
                    TextField("영단어", text: $word.english)
                        .autocorrectionDisabled()
                    TextField("한국어 뜻", text: $word.meaningKo)
                    TextField("메모", text: $word.note)
                    TextField("TOEIC 태그", text: $word.toeicTag)
                }

                Section("예문") {
                    TextField("영어 예문", text: $word.exampleEn, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("한국어 예문", text: $word.exampleKo, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("단어 편집")
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
