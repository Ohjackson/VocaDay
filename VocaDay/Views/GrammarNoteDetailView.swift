import SwiftData
import SwiftUI

struct GrammarNoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: GrammarNote

    @State private var isShowingEditor = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if note.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        title: "아직 내용이 없습니다. 이 노트를 편집해 Markdown을 붙여넣으세요.",
                        systemImage: "doc.text"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    GrammarMarkdownView(markdown: note.markdown)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle(note.title)
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    note.isFavorite.toggle()
                    note.updatedAt = Date()
                    try? modelContext.save()
                } label: {
                    Image(systemName: note.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(note.isFavorite ? "즐겨찾기 해제" : "즐겨찾기에 추가")

                Button {
                    note.isCompleted.toggle()
                    note.updatedAt = Date()
                    try? modelContext.save()
                } label: {
                    Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(note.isCompleted ? "완료 해제" : "완료로 표시")

                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("편집")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("삭제")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            GrammarNoteEditorView(note: note)
        }
        .confirmationDialog("이 문법 노트를 삭제할까요?", isPresented: $isShowingDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                modelContext.delete(note)
                try? modelContext.save()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기와 동기화된 SwiftData 저장소에서 Markdown 노트를 삭제합니다.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            HStack(spacing: 8) {
                if note.isCompleted {
                    Label("완료", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }

                Text(note.updatedAt, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

struct GrammarNoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let note: GrammarNote?

    @State private var title: String
    @State private var markdown: String
    @State private var isShowingPreview = false

    init(note: GrammarNote?) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _markdown = State(initialValue: note?.markdown ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                editorPanel

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.background)
            .navigationTitle(note == nil ? "새 문법 노트" : "문법 노트 편집")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $isShowingPreview) {
            GrammarMarkdownPreviewSheet(title: title, markdown: markdown)
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 520)
        #endif
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        if let note {
            note.title = cleanTitle
            note.markdown = markdown
            note.updatedAt = now
        } else {
            let newNote = GrammarNote(
                title: cleanTitle,
                markdown: markdown,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(newNote)
        }

        try? modelContext.save()
    }

    private var markdownSummary: String {
        let lineCount = markdown.components(separatedBy: .newlines).count
        return "\(lineCount)줄"
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("제목", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Markdown")
                    .font(.headline)

                Spacer()

                Text(markdownSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $markdown)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous)
                        .stroke(AppTheme.softStroke)
                }
                .frame(height: 178)

            Button {
                isShowingPreview = true
            } label: {
                Label("미리 보기", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 330, alignment: .topLeading)
        .calmCard()
    }
}

private struct GrammarMarkdownPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let markdown: String

    var body: some View {
        NavigationStack {
            ScrollView {
                GrammarMarkdownView(markdown: markdown)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 900, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(AppTheme.background)
            .navigationTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "미리 보기" : title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 640)
        #endif
    }
}

#Preview {
    NavigationStack {
        GrammarNoteDetailView(
            note: GrammarNote(
                title: "English Prepositions",
                markdown: """
                # English Prepositions

                ## Core List

                | Preposition | Image | Meaning |
                | --- | --- | --- |
                | in | inside | in, during |
                | on | contact | on, date |

                **Key:** Use at for a point, on for a date, and in for a wider time range.
                """
            )
        )
    }
    .modelContainer(for: [GrammarNote.self], inMemory: true)
}
