import SwiftData
import SwiftUI

struct DayWordsDetailView: View {
    let initialDay: VocabularyDay

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var currentDayID: UUID
    @State private var sortsWordsByCount = false
    @State private var selectedWordIDs: Set<UUID> = []
    @State private var editingWord: VocaWord?

    init(initialDay: VocabularyDay) {
        self.initialDay = initialDay
        _currentDayID = State(initialValue: initialDay.id)
    }

    private var currentDay: VocabularyDay {
        days.first { $0.id == currentDayID } ?? initialDay
    }

    private var orderedWords: [VocaWord] {
        if sortsWordsByCount {
            return currentDay.wordList.sorted {
                if $0.wrongCount == $1.wrongCount {
                    return $0.createdAt < $1.createdAt
                }

                return $0.wrongCount > $1.wrongCount
            }
        }

        return currentDay.wordList.sorted { $0.createdAt < $1.createdAt }
    }

    private var selectedWords: [VocaWord] {
        orderedWords.filter { selectedWordIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WordDataTable(
                    title: "\(currentDay.title) Words",
                    words: orderedWords,
                    allowsSelection: true,
                    showsTitle: false,
                    selectedWordIDs: $selectedWordIDs
                )
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle(currentDay.title)
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Text("\(orderedWords.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: speechPlayer.isPlaying ? "stop.fill" : "play.fill")
                }
                .disabled(orderedWords.isEmpty)
                .accessibilityLabel(speechPlayer.isPlaying ? "Stop" : "Play")

                Button {
                    editingWord = selectedWords.first
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(selectedWords.count != 1)
                .accessibilityLabel("Edit")

                Button(role: .destructive) {
                    deleteSelectedWords()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedWords.isEmpty)
                .accessibilityLabel("Delete")

                Button {
                    sortsWordsByCount.toggle()
                } label: {
                    Image(systemName: sortsWordsByCount ? "arrow.down.123" : "number")
                }
                .accessibilityLabel("Count Order")
            }
        }
        .sheet(item: $editingWord) { word in
            EditWordSheet(word: word) {
                try? modelContext.save()
                selectedWordIDs = [word.id]
            }
        }
        .onChange(of: currentDayID) { _, _ in
            selectedWordIDs.removeAll()
        }
        .onDisappear {
            speechPlayer.stop()
        }
    }

    private func togglePlayback() {
        if speechPlayer.isPlaying {
            speechPlayer.stop()
            return
        }

        let playingDay = currentDay
        speechPlayer.play(words: orderedWords) {
            moveToNextDay(after: playingDay)
        }
    }

    private func moveToNextDay(after day: VocabularyDay) {
        guard let currentIndex = days.firstIndex(where: { $0.id == day.id }) else { return }
        let nextIndex = days.index(after: currentIndex)
        guard days.indices.contains(nextIndex) else { return }
        currentDayID = days[nextIndex].id
    }

    private func deleteSelectedWords() {
        speechPlayer.stop()

        let wordsToDelete = selectedWords
        for word in wordsToDelete {
            currentDay.removeWord(word)
            modelContext.delete(word)
        }

        selectedWordIDs.removeAll()
        try? modelContext.save()
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

private struct EditWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var word: VocaWord
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("English", text: $word.english)
                    TextField("Korean Meaning", text: $word.meaningKo)
                    TextField("Note", text: $word.note)
                    TextField("TOEIC Tag", text: $word.toeicTag)
                }

                Section("Example") {
                    TextField("English Example", text: $word.exampleEn, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Korean Example", text: $word.exampleKo, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Edit Word")
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(word.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }
}
