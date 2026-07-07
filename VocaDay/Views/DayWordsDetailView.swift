import SwiftData
import SwiftUI

struct DayWordsDetailView: View {
    let initialDay: VocabularyDay

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var currentDayID: UUID
    @State private var sortsWordsByCount = false
    @State private var showsWordDetails = false
    @State private var selectedWordIDs: Set<UUID> = []
    @State private var editingWord: VocaWord?
    @State private var searchText = ""

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
        visibleWords.filter { selectedWordIDs.contains($0.id) }
    }

    private var visibleWords: [VocaWord] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return orderedWords }

        return orderedWords.filter { word in
            word.english.localizedCaseInsensitiveContains(query) ||
            word.meaningKo.localizedCaseInsensitiveContains(query) ||
            word.exampleEn.localizedCaseInsensitiveContains(query) ||
            word.exampleKo.localizedCaseInsensitiveContains(query) ||
            word.note.localizedCaseInsensitiveContains(query) ||
            word.toeicTag.localizedCaseInsensitiveContains(query)
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WordDataTable(
                    title: "\(currentDay.title) Words",
                    words: visibleWords,
                    allowsSelection: true,
                    showsTitle: false,
                    showsWordDetails: showsWordDetails,
                    emptyTitle: normalizedSearchText.isEmpty ? "No saved words in this Day." : "No matching words.",
                    selectedWordIDs: $selectedWordIDs
                )
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .navigationTitle(currentDay.title)
        .searchable(text: $searchText, prompt: "Search Words")
        .toolbar {
            ToolbarItemGroup(placement: toolbarPlacement) {
                Text(countText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $showsWordDetails) {
                    Image(systemName: "text.justify")
                }
                .toggleStyle(.button)
                .accessibilityLabel(showsWordDetails ? "Hide Word Details" : "Show Word Details")
                .disabled(visibleWords.isEmpty)

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: speechPlayer.isPlaying ? "stop.fill" : "play.fill")
                }
                .disabled(visibleWords.isEmpty)
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
        .onChange(of: searchText) { _, _ in
            selectedWordIDs = selectedWordIDs.intersection(Set(visibleWords.map(\.id)))
        }
        .onDisappear {
            speechPlayer.stop()
        }
    }

    private var countText: String {
        normalizedSearchText.isEmpty ? "\(orderedWords.count)" : "\(visibleWords.count)/\(orderedWords.count)"
    }

    private func togglePlayback() {
        if speechPlayer.isPlaying {
            speechPlayer.stop()
            return
        }

        let playingDay = currentDay
        speechPlayer.play(words: visibleWords) {
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
