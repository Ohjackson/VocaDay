import SwiftData
import SwiftUI
import Translation

private struct PendingTranslation: Identifiable, Equatable {
    let id: UUID
    let english: String
}

private struct DuplicateWordLocation: Identifiable, Hashable {
    var id: String { english.normalizedEnglish }
    let english: String
    let dayTitles: [String]
}

private struct DuplicateSaveConfirmation: Identifiable {
    let id = UUID()
    let locations: [DuplicateWordLocation]

    var normalizedEnglishSet: Set<String> {
        Set(locations.map { $0.english.normalizedEnglish })
    }

    var message: String {
        let locationText = locations
            .map { "\($0.english): \($0.dayTitles.joined(separator: ", "))" }
            .joined(separator: "\n")

        return locationText + "\n\n" + String(localized: "This word is already saved. You can still add it, or save without the duplicates.")
    }
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
    @State private var duplicateSaveConfirmation: DuplicateSaveConfirmation?
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
        .alert("Saved word already exists", isPresented: isDuplicateSaveConfirmationPresented) {
            Button("Add Anyway") {
                saveAllowingDuplicateEnglish()
            }

            Button("Save Without Duplicates") {
                saveSkippingDuplicateEnglish()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(duplicateSaveConfirmation?.message ?? "")
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
        guard !english.isEmpty else {
            importJSONFromClipboard(showAlerts: false)
            return
        }

        if english.looksLikeJSONArray {
            if importJSON(from: english) {
                inputWord = ""
                isInputFocused = true
            }
            return
        }

        guard !temporaryWords.contains(where: { $0.english.normalizedEnglish == english.normalizedEnglish }) else {
            inputWord = ""
            isInputFocused = true
            return
        }

        // Create immediately for responsiveness with a placeholder translation
        var word = VocaWordJSON(english: english)
        word.meaningKo = String(localized: "(Translating...)")
        temporaryWords.append(word)
        selectedTemporaryWordID = word.id
        inputWord = ""
        isInputFocused = true

        enqueueTranslation(for: word.id, english: english)
    }

    private func copyJSON() {
        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: String(localized: "No Words"), message: String(localized: "No words yet. Start by typing an English word."))
            return
        }

        do {
            struct ExportWordJSON: Codable {
                let english: String
                let meaningKo: String
                let exampleEn: String?
                let exampleKo: String?
                let note: String?
                let toeicTag: String?
            }
            let exportWords = temporaryWords.map { w in
                ExportWordJSON(
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
            alert = VocaAlert(title: String(localized: "Copy Failed"), message: error.localizedDescription)
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
                updateTemporaryWord(id: translation.id, meaningKo: korean.isEmpty ? String(localized: "(Translation failed)") : korean)
            } catch {
                updateTemporaryWord(id: translation.id, meaningKo: String(localized: "(Translation failed)"))
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
        importJSONFromClipboard(showAlerts: true)
    }

    @discardableResult
    private func importJSONFromClipboard(showAlerts: Bool) -> Bool {
        guard let text = ClipboardService.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if showAlerts {
                alert = VocaAlert(title: String(localized: "Clipboard Empty"), message: String(localized: "Copy enriched JSON first, then paste it here."))
            }
            return false
        }

        return importJSON(from: text, showAlerts: showAlerts)
    }

    @discardableResult
    private func importJSON(from text: String, showAlerts: Bool = true) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if showAlerts {
                alert = VocaAlert(title: String(localized: "JSON Empty"), message: String(localized: "Paste a JSON array before importing."))
            }
            return false
        }

        do {
            let decodedWords = try JSONWordParser.decode(text)
            let firstDecodedEnglish = decodedWords.first?.english.normalizedEnglish
            let decodedEnglishSet = Set(decodedWords.map { $0.english.normalizedEnglish })
            var existingWordsByEnglish: [String: VocaWordJSON] = [:]
            for temporaryWord in temporaryWords {
                existingWordsByEnglish[temporaryWord.english.normalizedEnglish] = temporaryWord
            }
            let remainingWords = temporaryWords.filter {
                !decodedEnglishSet.contains($0.english.normalizedEnglish)
            }
            var importedWords: [VocaWordJSON] = []

            for decodedWord in decodedWords {
                let normalizedEnglish = decodedWord.english.normalizedEnglish
                if var existingWord = existingWordsByEnglish.removeValue(forKey: normalizedEnglish) {
                    existingWord.meaningKo = decodedWord.meaningKo
                    existingWord.exampleEn = decodedWord.exampleEn
                    existingWord.exampleKo = decodedWord.exampleKo
                    existingWord.note = decodedWord.note
                    existingWord.toeicTag = decodedWord.toeicTag
                    importedWords.append(existingWord)
                } else {
                    importedWords.append(decodedWord)
                }
            }
            temporaryWords = importedWords + remainingWords

            if let firstDecodedEnglish,
               let importedWord = temporaryWords.first(where: { $0.english.normalizedEnglish == firstDecodedEnglish }) {
                selectedTemporaryWordID = importedWord.id
            }
            if showAlerts {
                let message = decodedWords.count == 1
                    ? String(localized: "1 word processed.")
                    : String(format: String(localized: "%lld words processed."), decodedWords.count)
                alert = VocaAlert(title: String(localized: "JSON Imported"), message: message)
            }
            return true
        } catch {
            if showAlerts {
                alert = VocaAlert(title: String(localized: "Invalid JSON"), message: String(localized: "Paste a JSON array using english, meaningKo, exampleEn, exampleKo, note, and toeicTag fields."))
            }
            return false
        }
    }

    private func showCopiedMessage() {
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedMessage = String(localized: "JSON copied")
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
        guard selectedDay != nil else {
            alert = VocaAlert(title: String(localized: "No Selected Day"), message: String(localized: "Create or select a Day before saving words."))
            return
        }

        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: String(localized: "No Words"), message: String(localized: "No words yet. Start by typing an English word."))
            return
        }

        let duplicateLocations = existingWordLocations(for: temporaryWords)
        guard duplicateLocations.isEmpty else {
            duplicateSaveConfirmation = DuplicateSaveConfirmation(locations: duplicateLocations)
            return
        }

        saveTemporaryWords(skippingNormalizedEnglish: [], allowDuplicateEnglish: false)
    }

    private func saveAllowingDuplicateEnglish() {
        duplicateSaveConfirmation = nil
        saveTemporaryWords(
            skippingNormalizedEnglish: [],
            allowDuplicateEnglish: true
        )
    }

    private func saveSkippingDuplicateEnglish() {
        let skippingEnglish = duplicateSaveConfirmation?.normalizedEnglishSet ?? []
        duplicateSaveConfirmation = nil
        saveTemporaryWords(
            skippingNormalizedEnglish: skippingEnglish,
            allowDuplicateEnglish: false
        )
    }

    private func saveTemporaryWords(
        skippingNormalizedEnglish: Set<String>,
        allowDuplicateEnglish: Bool
    ) {
        guard let selectedDay = selectedDay else {
            alert = VocaAlert(title: String(localized: "No Selected Day"), message: String(localized: "Create or select a Day before saving words."))
            return
        }

        var existingEnglish = allowDuplicateEnglish
            ? Set<String>()
            : Set(selectedDay.wordList.map { $0.english.normalizedEnglish })
        var insertedCount = 0

        for temporaryWord in temporaryWords {
            let normalizedEnglish = temporaryWord.english.normalizedEnglish
            guard !skippingNormalizedEnglish.contains(normalizedEnglish) else { continue }
            guard allowDuplicateEnglish || !existingEnglish.contains(normalizedEnglish) else { continue }

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
            existingEnglish.insert(normalizedEnglish)
            insertedCount += 1
        }

        do {
            try modelContext.save()
            temporaryWords.removeAll()
            selectedTemporaryWordID = nil
            let message = insertedCount == 1
                ? String(format: String(localized: "1 word saved to %@."), selectedDay.title)
                : String(format: String(localized: "%lld words saved to %@."), insertedCount, selectedDay.title)
            alert = VocaAlert(title: String(localized: "Saved"), message: message)
            isInputFocused = true
        } catch {
            alert = VocaAlert(title: String(localized: "Save Failed"), message: error.localizedDescription)
        }
    }

    private func existingWordLocations(for words: [VocaWordJSON]) -> [DuplicateWordLocation] {
        let targetEnglish = Set(words.map { $0.english.normalizedEnglish }.filter { !$0.isEmpty })
        guard !targetEnglish.isEmpty else { return [] }

        var titlesByEnglish: [String: Set<String>] = [:]
        for day in days {
            for word in day.wordList {
                let normalizedEnglish = word.english.normalizedEnglish
                guard targetEnglish.contains(normalizedEnglish) else { continue }
                titlesByEnglish[normalizedEnglish, default: []].insert(day.title)
            }
        }

        var seenEnglish: Set<String> = []
        return words.compactMap { word in
            let normalizedEnglish = word.english.normalizedEnglish
            guard !seenEnglish.contains(normalizedEnglish),
                  let dayTitles = titlesByEnglish[normalizedEnglish] else {
                return nil
            }

            seenEnglish.insert(normalizedEnglish)
            return DuplicateWordLocation(
                english: word.english,
                dayTitles: dayTitles.sorted()
            )
        }
    }

    private var selectedDay: VocabularyDay? {
        guard let selectedDayID else { return days.first }
        return days.first { $0.id == selectedDayID } ?? days.first
    }

    private var isDuplicateSaveConfirmationPresented: Binding<Bool> {
        Binding(
            get: { duplicateSaveConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    duplicateSaveConfirmation = nil
                }
            }
        )
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

    var looksLikeJSONArray: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }
}

#Preview {
    NavigationStack {
        AddWordsView(selectedDayID: .constant(nil))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
