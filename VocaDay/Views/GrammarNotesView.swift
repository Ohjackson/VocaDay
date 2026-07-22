import SwiftData
import SwiftUI

struct GrammarNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GrammarNote.updatedAt, order: .reverse) private var notes: [GrammarNote]

    @State private var searchText = ""
    @State private var editingNote: GrammarNote?
    @State private var isShowingEditor = false
    @State private var isEditingList = false

    private var filteredNotes: [GrammarNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }

        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query) ||
            note.markdown.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if notes.isEmpty {
                    EmptyStateView(
                        title: "No grammar notes yet. Paste Markdown to create one.",
                        systemImage: "text.book.closed"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else if filteredNotes.isEmpty {
                    EmptyStateView(
                        title: "No matching grammar notes.",
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredNotes) { note in
                            noteRow(note)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("Grammar Notes")
        .searchable(text: $searchText, prompt: "Search Grammar Notes")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    isEditingList.toggle()
                } label: {
                    Image(systemName: isEditingList ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingList ? "Done Editing Grammar Notes" : "Edit Grammar Notes")
                .disabled(notes.isEmpty)

                Button {
                    editingNote = nil
                    isShowingEditor = true
                } label: {
                    Label("New Grammar Note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            GrammarNoteEditorView(note: editingNote)
        }
    }

    @ViewBuilder
    private func noteRow(_ note: GrammarNote) -> some View {
        if isEditingList {
            HStack(spacing: 10) {
                GrammarNoteRowView(note: note)

                Button {
                    editingNote = note
                    isShowingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit \(note.title)")

                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(note.title)")
            }
        } else {
            NavigationLink {
                GrammarNoteDetailView(note: note)
            } label: {
                GrammarNoteRowView(note: note)
            }
            .buttonStyle(.plain)
        }
    }

    private func delete(_ note: GrammarNote) {
        modelContext.delete(note)
        try? modelContext.save()

        if notes.count <= 1 {
            isEditingList = false
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

struct GrammarNoteRowView: View {
    let note: GrammarNote

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "doc.text")
                .font(.title3)
                .foregroundStyle(note.isCompleted ? .green : .secondary)
                .frame(width: 32, height: 32)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                Text(note.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(note.updatedAt, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .topLeading)
        .calmCard()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        GrammarNotesView()
    }
    .modelContainer(for: [GrammarNote.self], inMemory: true)
}
