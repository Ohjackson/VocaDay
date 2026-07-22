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
                        title: "No content yet. Edit this note and paste Markdown.",
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
                .accessibilityLabel(note.isFavorite ? "Remove Favorite" : "Add Favorite")

                Button {
                    note.isCompleted.toggle()
                    note.updatedAt = Date()
                    try? modelContext.save()
                } label: {
                    Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(note.isCompleted ? "Mark Incomplete" : "Mark Complete")

                Button {
                    isShowingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            GrammarNoteEditorView(note: note)
        }
        .confirmationDialog("Delete this grammar note?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(note)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Markdown note from this device and synced SwiftData store.")
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
                    Label("Completed", systemImage: "checkmark.circle.fill")
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
            .navigationTitle(note == nil ? "New Grammar Note" : "Edit Grammar Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
        return String(format: String(localized: "%lld lines"), lineCount)
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.softStroke)
                }
                .frame(height: 178)

            Button {
                isShowingPreview = true
            } label: {
                Label("Preview", systemImage: "eye")
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
            .navigationTitle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "Preview") : title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
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
