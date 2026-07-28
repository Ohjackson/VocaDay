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

enum AddEntryMode: String, CaseIterable, Identifiable {
    case manual
    case json

    var id: Self { self }

    var title: String {
        switch self {
        case .manual: "직접 입력"
        case .json: "JSON 가져오기"
        }
    }
}

struct AddWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

    @Binding var selectedDayID: UUID?
    @Binding var quickAddWord: String?
    @Binding var entryMode: AddEntryMode
    @State private var inputWord = ""
    @State private var jsonInput = ""
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

                    entryModePicker

                    TemporaryWordTable(
                        words: temporaryWords,
                        selectedWordID: $selectedTemporaryWordID
                    )

                    entryInputCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }

            actionBar
        }
        .background(AppTheme.background)
        .navigationTitle("단어 추가")
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
                dismissButton: .default(Text("확인"))
            )
        }
        .onAppear {
            ensureSelectedDay()
            consumeQuickAddWord()
            isInputFocused = true
        }
        .onChange(of: days.map(\.id)) { _, _ in
            ensureSelectedDay()
        }
        .onChange(of: quickAddWord) { _, _ in
            consumeQuickAddWord()
        }
        .translationTask(translationConfiguration) { session in
            await translatePendingWords(with: session)
        }
    }

    private var selectedDayPicker: some View {
        HStack(spacing: 14) {
            Text("선택한 데이")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if days.isEmpty {
                Button {
                    let day = DayFactory.createNextDay(existingDays: days, in: modelContext)
                    selectedDayID = day.id
                } label: {
                    Label("첫 데이 만들기", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Picker("선택한 데이", selection: $selectedDayID) {
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

    private var entryModePicker: some View {
        Picker("입력 방식", selection: $entryMode) {
            ForEach(AddEntryMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onboardingSpotlight(.addMode)
    }

    @ViewBuilder
    private var entryInputCard: some View {
        switch entryMode {
        case .manual:
            WordInputCard(
                inputWord: $inputWord,
                isInputFocused: $isInputFocused,
                onSubmit: addInputWord
            )
            .padding(.top, 18)
        case .json:
            jsonInputCard
                .padding(.top, 18)
        }
    }

    private var jsonInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("JSON 입력", systemImage: "curlybraces.square")
                    .font(.headline)

                Spacer()

                Button("JSON 붙여넣기") {
                    pasteJSONIntoEditor()
                }
                .buttonStyle(.bordered)
            }

            Text("english, meaningKo, 예문, 메모, 태그를 포함한 JSON 배열을 붙여넣으세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $jsonInput)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled()

            Button {
                importJSONFromEditor()
            } label: {
                Label("JSON 가져오기", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .calmCard()
        .onboardingSpotlight(.jsonInput)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Divider()

            #if os(iOS)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                actionButton(title: "JSON 붙여넣기", systemImage: "doc.on.clipboard", action: pasteJSON)
                actionButton(title: "JSON 복사", systemImage: "doc.on.doc", isDisabled: temporaryWords.isEmpty, action: copyJSON)
                actionButton(title: "삭제", systemImage: "trash", role: .destructive, isDisabled: selectedTemporaryWordID == nil) {
                    deleteSelectedTemporaryWord()
                    isInputFocused = true
                }
                actionButton(title: "데이에 저장", systemImage: "tray.and.arrow.down", isProminent: true, isDisabled: temporaryWords.isEmpty, action: saveToDay)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            #else
            HStack(spacing: 20) {
                Button {
                    pasteJSON()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("JSON 붙여넣기")
                .help("JSON 붙여넣기")

                Button {
                    copyJSON()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .disabled(temporaryWords.isEmpty)
                .accessibilityLabel("JSON 복사")
                .help("JSON 복사")

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
                .accessibilityLabel("삭제")
                .help("삭제")

                Button {
                    saveToDay()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(temporaryWords.isEmpty)
                .accessibilityLabel("데이에 저장")
                .help("데이에 저장")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            #endif
        }
        .background(.regularMaterial)
        .onboardingSpotlight(.addActions)
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isProminent: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if isProminent {
            Button(role: role, action: action) {
                actionButtonLabel(title: title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
            .accessibilityLabel(Text(title))
        } else {
            Button(role: role, action: action) {
                actionButtonLabel(title: title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
            .accessibilityLabel(Text(title))
        }
    }

    private func actionButtonLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
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

        addEnglishWord(english)
    }

    private func addEnglishWord(_ english: String) {
        guard !temporaryWords.contains(where: { $0.english.normalizedEnglish == english.normalizedEnglish }) else {
            alert = VocaAlert(
                title: "중복 단어",
                message: "\"\(english)\"은(는) 이미 임시 목록에 있습니다."
            )
            inputWord = ""
            isInputFocused = true
            return
        }

        if let duplicateLocation = existingWordLocation(forNormalizedEnglish: english.normalizedEnglish) {
            alert = VocaAlert(
                title: "중복 단어",
                message: "\"\(english)\"은(는) 이미 \(duplicateLocation.dayTitles.joined(separator: ", "))에 있습니다."
            )
            inputWord = ""
            isInputFocused = true
            return
        }

        // Create immediately for responsiveness with a placeholder translation
        var word = VocaWordJSON(english: english)
        word.meaningKo = "(번역 중...)"
        temporaryWords.append(word)
        selectedTemporaryWordID = word.id
        inputWord = ""
        isInputFocused = true

        enqueueTranslation(for: word.id, english: english)
    }

    private func consumeQuickAddWord() {
        guard let word = quickAddWord?.trimmingCharacters(in: .whitespacesAndNewlines),
              !word.isEmpty else {
            return
        }

        quickAddWord = nil
        addEnglishWord(word)
    }

    private func copyJSON() {
        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: "단어 없음", message: "아직 단어가 없습니다. 영단어를 입력해 시작하세요.")
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
            alert = VocaAlert(title: "복사 실패", message: error.localizedDescription)
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
                updateTemporaryWord(id: translation.id, meaningKo: korean.isEmpty ? "(번역 실패)" : korean)
            } catch {
                updateTemporaryWord(id: translation.id, meaningKo: "(번역 실패)")
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
        if entryMode == .json {
            pasteJSONIntoEditor()
        } else {
            importJSONFromClipboard(showAlerts: true)
        }
    }

    private func pasteJSONIntoEditor() {
        guard let text = ClipboardService.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = VocaAlert(title: "클립보드 비어 있음", message: "먼저 JSON을 복사한 뒤 여기에 붙여넣으세요.")
            return
        }

        jsonInput = text
    }

    private func importJSONFromEditor() {
        if importJSON(from: jsonInput) {
            jsonInput = ""
        }
    }

    @discardableResult
    private func importJSONFromClipboard(showAlerts: Bool) -> Bool {
        guard let text = ClipboardService.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if showAlerts {
                alert = VocaAlert(title: "클립보드 비어 있음", message: "먼저 JSON을 복사한 뒤 여기에 붙여넣으세요.")
            }
            return false
        }

        return importJSON(from: text, showAlerts: showAlerts)
    }

    @discardableResult
    private func importJSON(from text: String, showAlerts: Bool = true) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if showAlerts {
                alert = VocaAlert(title: "JSON 비어 있음", message: "가져오기 전에 JSON 배열을 붙여넣으세요.")
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
                    ? "단어 1개를 처리했습니다."
                    : "단어 \(decodedWords.count)개를 처리했습니다."
                alert = VocaAlert(title: "JSON 가져오기 완료", message: message)
            }
            return true
        } catch {
            if showAlerts {
                alert = VocaAlert(title: "잘못된 JSON", message: "english, meaningKo, exampleEn, exampleKo, note, toeicTag 필드를 사용하는 JSON 배열을 붙여넣으세요.")
            }
            return false
        }
    }

    private func showCopiedMessage() {
        withAnimation(.easeInOut(duration: 0.18)) {
            copiedMessage = "JSON을 복사했습니다"
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
            alert = VocaAlert(title: "선택한 데이 없음", message: "단어를 저장하기 전에 데이를 만들거나 선택하세요.")
            return
        }

        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(title: "단어 없음", message: "아직 단어가 없습니다. 영단어를 입력해 시작하세요.")
            return
        }

        let duplicateLocations = existingWordLocations(for: temporaryWords)
        guard duplicateLocations.isEmpty else {
            alert = VocaAlert(
                title: "중복 단어",
                message: duplicateMessage(for: duplicateLocations)
            )
            return
        }

        saveTemporaryWords(skippingNormalizedEnglish: [], allowDuplicateEnglish: false)
    }

    private func saveTemporaryWords(
        skippingNormalizedEnglish: Set<String>,
        allowDuplicateEnglish: Bool
    ) {
        guard let selectedDay = selectedDay else {
            alert = VocaAlert(title: "선택한 데이 없음", message: "단어를 저장하기 전에 데이를 만들거나 선택하세요.")
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
                ? "단어 1개를 \(selectedDay.title)에 저장했습니다."
                : "단어 \(insertedCount)개를 \(selectedDay.title)에 저장했습니다."
            alert = VocaAlert(title: "저장 완료", message: message)
            isInputFocused = true
        } catch {
            alert = VocaAlert(title: "저장 실패", message: error.localizedDescription)
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

    private func existingWordLocation(forNormalizedEnglish normalizedEnglish: String) -> DuplicateWordLocation? {
        guard !normalizedEnglish.isEmpty else { return nil }

        let dayTitles = days.compactMap { day in
            day.wordList.contains { $0.english.normalizedEnglish == normalizedEnglish } ? day.title : nil
        }

        guard !dayTitles.isEmpty else { return nil }
        return DuplicateWordLocation(english: normalizedEnglish, dayTitles: dayTitles)
    }

    private func duplicateMessage(for locations: [DuplicateWordLocation]) -> String {
        let locationText = locations
            .map { "\($0.english): \($0.dayTitles.joined(separator: ", "))" }
            .joined(separator: "\n")

        return locationText + "\n\n" + "같은 철자의 단어는 두 번 추가할 수 없습니다."
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
        AddWordsView(selectedDayID: .constant(nil), quickAddWord: .constant(nil), entryMode: .constant(.manual))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
