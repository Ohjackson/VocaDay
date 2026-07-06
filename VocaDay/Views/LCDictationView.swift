import SwiftData
import SwiftUI

struct LCDictationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LCDictationDay.createdAt) private var days: [LCDictationDay]

    @State private var isEditingDays = false
    @State private var isShowingNewDayAlert = false
    @State private var newDayTitle = ""
    @State private var editingDay: LCDictationDay?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if days.isEmpty {
                    EmptyStateView(
                        title: "No LC dictation day exists yet.",
                        systemImage: "headphones"
                    )
                    .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(days) { day in
                            dayRow(for: day)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 840, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle("LC Dictation")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Button {
                    isEditingDays.toggle()
                } label: {
                    Image(systemName: isEditingDays ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingDays ? "Done Editing LC Days" : "Edit LC Days")
                .disabled(days.isEmpty)

                Button {
                    newDayTitle = ""
                    editingDay = nil
                    isShowingNewDayAlert = true
                } label: {
                    Label("New LC Day", systemImage: "plus")
                }
            }
        }
        .alert(editingDay == nil ? "New LC Day" : "Edit LC Day", isPresented: $isShowingNewDayAlert) {
            TextField("Title", text: $newDayTitle)

            Button("Cancel", role: .cancel) {
                newDayTitle = ""
            }

            Button(editingDay == nil ? "Create" : "Save") {
                saveDayTitle()
            }
            .disabled(newDayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a title for this dictation note.")
        }
    }

    @ViewBuilder
    private func dayRow(for day: LCDictationDay) -> some View {
        if isEditingDays {
            HStack(spacing: 10) {
                LCDictationDayCardView(day: day)

                Button {
                    editingDay = day
                    newDayTitle = day.title
                    isShowingNewDayAlert = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Rename \(day.title)")

                Button(role: .destructive) {
                    delete(day)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(day.title)")
            }
        } else {
            NavigationLink {
                LCDictationDetailView(day: day)
            } label: {
                LCDictationDayCardView(day: day)
            }
            .buttonStyle(.plain)
        }
    }

    private func saveDayTitle() {
        let title = newDayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        if let editingDay {
            editingDay.title = title
        } else {
            let day = LCDictationDay(title: title)
            let firstNote = LCDictationNote(day: day)
            day.appendNote(firstNote)
            modelContext.insert(day)
            modelContext.insert(firstNote)
        }

        try? modelContext.save()

        editingDay = nil
        newDayTitle = ""
    }

    private func delete(_ day: LCDictationDay) {
        modelContext.delete(day)
        try? modelContext.save()

        if days.count <= 1 {
            isEditingDays = false
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

private struct LCDictationDetailView: View {
    let day: LCDictationDay

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingNotes = false
    @FocusState private var focusedNoteID: UUID?

    private var notes: [LCDictationNote] {
        day.noteList.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(day.title)
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Text("\(notes.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    isEditingNotes.toggle()
                } label: {
                    Image(systemName: isEditingNotes ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingNotes ? "Done Editing Notes" : "Edit Notes")

                Button {
                    addNoteAndFocus()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Note")
            }
        }
        .task {
            ensureInitialNote()
        }
    }

    private func noteRow(_ note: LCDictationNote, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                }
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                TextField("English dictation", text: Bindable(note).text, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .submitLabel(.next)
                    .focused($focusedNoteID, equals: note.id)
                    .onSubmit {
                        focusNextOrCreate(after: note)
                    }
                    .disabled(isEditingNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if note.text.isEmpty {
                    Text("Press Enter to add the next line")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditingNotes {
                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete note \(index + 1)")
                .padding(.top, 7)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.cardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focusedNoteID == note.id ? Color.accentColor.opacity(0.45) : AppTheme.softStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            focusedNoteID = note.id
        }
    }

    private func ensureInitialNote() {
        guard notes.isEmpty else { return }
        addNoteAndFocus()
    }

    private func focusNextOrCreate(after note: LCDictationNote) {
        let orderedNotes = notes
        guard let index = orderedNotes.firstIndex(where: { $0.id == note.id }) else {
            addNoteAndFocus()
            return
        }

        if orderedNotes.indices.contains(index + 1) {
            focusedNoteID = orderedNotes[index + 1].id
        } else {
            addNoteAndFocus()
        }
    }

    private func addNoteAndFocus() {
        let note = LCDictationNote(day: day)
        day.appendNote(note)
        modelContext.insert(note)
        try? modelContext.save()

        Task { @MainActor in
            focusedNoteID = note.id
        }
    }

    private func delete(_ note: LCDictationNote) {
        let wasLastNote = notes.count <= 1
        let nextFocusID = notes.first { $0.id != note.id }?.id
        modelContext.delete(note)
        try? modelContext.save()

        if wasLastNote {
            isEditingNotes = false
            ensureInitialNote()
        } else {
            Task { @MainActor in
                focusedNoteID = nextFocusID
            }
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

private struct LCDictationDayCardView: View {
    let day: LCDictationDay

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("Created \(day.createdAt, format: .dateTime.month().day().year())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(day.noteList.count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 54, alignment: .trailing)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .calmCard()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        LCDictationView()
    }
    .modelContainer(for: [LCDictationDay.self, LCDictationNote.self], inMemory: true)
}
