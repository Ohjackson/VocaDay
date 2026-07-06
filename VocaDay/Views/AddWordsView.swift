import SwiftData
import SwiftUI
import Translation

private struct PendingTranslation: Identifiable, Equatable {
    let id: UUID
    let english: String
}

struct AddWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @Binding var selectedDayID: UUID?
    @State private var inputWord = ""
    @State private var temporaryWords: [VocaWordJSON] = []
    @State private var selectedTemporaryWordID: UUID?
    @State private var copiedMessage: String?
    @State private var alert: VocaAlert?
    @State private var pendingTranslations: [PendingTranslation] = []
    @State private var translationConfiguration: TranslationSession.Configuration?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    selectedDayPicker

                    TemporaryWordTable(
                        words: temporaryWords,
                        selectedWordID: $selectedTemporaryWordID
                    )

                    WordInputCard(
                        inputWord: $inputWord,
                        isInputFocused: $isInputFocused,
                        onSubmit: addInputWord
                    )
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }

            actionBar
        }
        .background(AppTheme.background)
        .navigationTitle("Add Words")
        .overlay(alignment: .top) {
            if let copiedMessage {
                Text(copiedMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            ensureSelectedDay()
            isInputFocused = true
        }
        .onChange(of: days.map(\.id)) { _, _ in
            ensureSelectedDay()
        }
        .translationTask(translationConfiguration) { session in
            await translatePendingWords(with: session)
        }
    }

    private var selectedDayPicker: some View {
        HStack(spacing: 14) {
            Text("Selected Day")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if days.isEmpty {
                Button {
                    let day = DayFactory.createNextDay(existingDays: days, in: modelContext)
                    selectedDayID = day.id
                } label: {
                    Label("Create Day 1", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Picker("Selected Day", selection: $selectedDayID) {
                    ForEach(days) { day in
                        Text(day.title).tag(Optional(day.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            Spacer()
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 20) {
                Button {
                    pasteJSON()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Paste JSON")
                .help("Paste JSON")

                Button {
                    copyJSON()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .disabled(temporaryWords.isEmpty)
                .accessibilityLabel("Copy JSON")
                .help("Copy JSON")

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    deleteSelectedTemporaryWord()
                    isInputFocused = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .disabled(selectedTemporaryWordID == nil)
                .accessibilityLabel("Delete")
                .help("Delete")

                Button {
                    saveToDay()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(temporaryWords.isEmpty)
                .accessibilityLabel("Save to Day")
                .help("Save to Day")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background(.regularMaterial)
    }

    private func addInputWord() {
        let english = inputWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !english.isEmpty else { return }

        guard !temporaryWords.contains(where: { $0.english.normalizedEnglish == english.normalizedEnglish }) else {
            inputWord = ""
            isInputFocused = true
            return
        }

        // Create immediately for responsiveness with a placeholder translation
        var word = VocaWordJSON(english: english)
        word.meaningKo = "(자동 번역 중…)"
        temporaryWords.append(word)
        selectedTemporaryWordID = word.id
        inputWord = ""
        isInputFocused = true

        enqueueTranslation(for: word.id, english: english)
    }

    private func copyJSON() {
        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: "No Words", message: "No words yet. Start by typing an English word.")
            return
        }

        do {
            struct ExportWordJSON: Codable {
                let id: UUID
                let english: String
                let meaningKo: String
                let exampleEn: String?
                let exampleKo: String?
                let note: String?
                let toeicTag: String?
            }
            let exportWords = temporaryWords.map { w in
                ExportWordJSON(
                    id: w.id,
                    english: w.english,
                    meaningKo: "",
                    exampleEn: w.exampleEn,
                    exampleKo: w.exampleKo,
                    note: w.note,
                    toeicTag: w.toeicTag
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportWords)
            let json = String(data: data, encoding: .utf8) ?? "[]"
            ClipboardService.copyText(json)
            showCopiedMessage()
        } catch {
            alert = VocaAlert(title: "Copy Failed", message: error.localizedDescription)
        }
    }

    private func enqueueTranslation(for id: UUID, english: String) {
        pendingTranslations.removeAll { $0.id == id }
        pendingTranslations.append(PendingTranslation(id: id, english: english))

        if translationConfiguration == nil {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ko")
            )
        } else {
            translationConfiguration?.invalidate()
        }
    }

    @MainActor
    private func consumePendingTranslations() -> [PendingTranslation] {
        let translations = pendingTranslations
        pendingTranslations.removeAll()
        return translations
    }

    private func translatePendingWords(with session: TranslationSession) async {
        let translations = consumePendingTranslations()
        guard !translations.isEmpty else { return }

        for translation in translations {
            do {
                let response = try await session.translate(translation.english)
                let korean = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                updateTemporaryWord(id: translation.id, meaningKo: korean.isEmpty ? "(자동 번역 실패)" : korean)
            } catch {
                updateTemporaryWord(id: translation.id, meaningKo: "(자동 번역 실패)")
                print("[Translate] Apple Translation error: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func updateTemporaryWord(id: UUID, meaningKo: String) {
        guard let index = temporaryWords.firstIndex(where: { $0.id == id }) else { return }
        temporaryWords[index].meaningKo = meaningKo
    }

    private func pasteJSON() {
        guard let text = ClipboardService.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = VocaAlert(title: "Clipboard Empty", message: "Copy enriched JSON first, then paste it here.")
            return
        }

        importJSON(from: text)
    }

    private func importJSON(from text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = VocaAlert(title: "JSON Empty", message: "Paste a JSON array before importing.")
            return
        }

        do {
            let decodedWords = try JSONWordParser.decode(text)
            let firstDecodedEnglish = decodedWords.first?.english.normalizedEnglish
            for decodedWord in decodedWords {
                if let index = temporaryWords.firstIndex(where: { $0.english.normalizedEnglish == decodedWord.english.normalizedEnglish }) {
                    temporaryWords[index].meaningKo = decodedWord.meaningKo
                    temporaryWords[index].exampleEn = decodedWord.exampleEn
                    temporaryWords[index].exampleKo = decodedWord.exampleKo
                    temporaryWords[index].note = decodedWord.note
                    temporaryWords[index].toeicTag = decodedWord.toeicTag
                } else {
                    temporaryWords.append(decodedWord)
                }
            }

            if let firstDecodedEnglish,
               let importedWord = temporaryWords.first(where: { $0.english.normalizedEnglish == firstDecodedEnglish }) {
                selectedTemporaryWordID = importedWord.id
            }
            alert = VocaAlert(title: "JSON Imported", message: "\(decodedWords.count) word\(decodedWords.count == 1 ? "" : "s") processed.")
        } catch {
            alert = VocaAlert(title: "Invalid JSON", message: "Paste a JSON array using english, meaningKo, exampleEn, exampleKo, note, and toeicTag fields.")
        }
    }

    private func showCopiedMessage() {
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedMessage = "JSON copied"
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeInOut(duration: 0.18)) {
                copiedMessage = nil
            }
        }
    }

    private func deleteSelectedTemporaryWord() {
        guard let selectedTemporaryWordID else { return }
        temporaryWords.removeAll { $0.id == selectedTemporaryWordID }
        self.selectedTemporaryWordID = temporaryWords.last?.id
    }

    private func saveToDay() {
        guard let selectedDay = selectedDay else {
            alert = VocaAlert(title: "No Selected Day", message: "Create or select a Day before saving words.")
            return
        }

        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: "No Words", message: "No words yet. Start by typing an English word.")
            return
        }

        var existingEnglish = Set(selectedDay.wordList.map { $0.english.normalizedEnglish })
        var insertedCount = 0

        for temporaryWord in temporaryWords where !existingEnglish.contains(temporaryWord.english.normalizedEnglish) {
            let word = VocaWord(
                english: temporaryWord.english,
                meaningKo: temporaryWord.meaningKo,
                exampleEn: temporaryWord.exampleEn,
                exampleKo: temporaryWord.exampleKo,
                note: temporaryWord.note,
                toeicTag: temporaryWord.toeicTag,
                nextReviewAt: Date(),
                day: selectedDay
            )
            modelContext.insert(word)
            selectedDay.appendWord(word)
            existingEnglish.insert(temporaryWord.english.normalizedEnglish)
            insertedCount += 1
        }

        do {
            try modelContext.save()
            temporaryWords.removeAll()
            selectedTemporaryWordID = nil
            alert = VocaAlert(title: "Saved", message: "\(insertedCount) new word\(insertedCount == 1 ? "" : "s") saved to \(selectedDay.title).")
            isInputFocused = true
        } catch {
            alert = VocaAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    private var selectedDay: VocabularyDay? {
        guard let selectedDayID else { return days.first }
        return days.first { $0.id == selectedDayID } ?? days.first
    }

    private func ensureSelectedDay() {
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }

        if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectedDayID = days.first?.id
    }
}

struct VocaAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension String {
    var normalizedEnglish: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#Preview {
    NavigationStack {
        AddWordsView(selectedDayID: .constant(nil))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
