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
    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @AppStorage("hasDismissedAddWordsGuide") private var hasDismissedAddWordsGuide = false
    @State private var inputWord = ""
    @State private var jsonInput = ""
    @State private var temporaryWords: [VocaWordJSON] = []
    @State private var selectedTemporaryWordID: UUID?
    @State private var copiedMessage: String?
    @State private var alert: VocaAlert?
    @State private var pendingTranslations: [PendingTranslation] = []
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isShowingGuideDismissalConfirmation = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    selectedDayPicker

                    if isJSONImportEnabled {
                        entryModePicker
                    }

                    if !hasDismissedAddWordsGuide {
                        usageGuide
                    }

                    entryInputCard

                    TemporaryWordTable(
                        words: $temporaryWords,
                        selectedWordID: $selectedTemporaryWordID
                    )
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
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                helpNavigationLink
            }
#else
            ToolbarItem(placement: .primaryAction) {
                helpNavigationLink
            }
#endif
        }
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
        .confirmationDialog(
            "단어 추가 방법 안내를 다시 보지 않을까요?",
            isPresented: $isShowingGuideDismissalConfirmation,
            titleVisibility: .visible
        ) {
            Button("확인", role: .destructive) {
                hasDismissedAddWordsGuide = true
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("확인을 누르면 다음부터 이 안내 상자가 표시되지 않습니다.")
        }
        .onAppear {
            ensureAvailableEntryMode()
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
        .onChange(of: isJSONImportEnabled) { _, _ in
            ensureAvailableEntryMode()
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

    private var usageGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("단어 추가 방법", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Button {
                    isShowingGuideDismissalConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("단어 추가 방법 안내 숨기기")
                .help("안내 숨기기")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(Array(usageGuideSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.accentColor, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                            Text(step.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(18)
        .calmCard()
    }

    private var helpNavigationLink: some View {
        NavigationLink {
            AddWordsHelpView()
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .accessibilityLabel("단어 추가 도움말")
        .help("단어 추가 도움말")
    }

    private var usageGuideSteps: [(title: String, message: String)] {
        if isJSONImportEnabled, entryMode == .json {
            return [
                ("데이 선택", "가져온 단어를 저장할 데이를 고르세요."),
                ("JSON 붙여넣기", "준비한 JSON 배열을 입력란에 붙여넣으세요."),
                ("목록 가져오기", "JSON 가져오기를 눌러 임시 목록을 확인하세요."),
                ("데이에 저장", "목록을 확인한 뒤 아래 저장 버튼을 누르세요.")
            ]
        }

        return [
            ("데이 선택", "단어를 저장할 데이를 고르세요."),
            ("영단어 입력", "아래 입력란에 영단어를 쓰고 Return을 누르세요."),
            ("목록 확인", "자동 번역된 뜻과 임시 단어를 확인하세요."),
            ("데이에 저장", "목록을 확인한 뒤 아래 저장 버튼을 누르세요.")
        ]
    }

    @ViewBuilder
    private var entryInputCard: some View {
        if isJSONImportEnabled, entryMode == .json {
            jsonInputCard
        } else {
            WordInputCard(
                inputWord: $inputWord,
                isInputFocused: $isInputFocused,
                onSubmit: addInputWord
            )
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
                if isJSONImportEnabled {
                    actionButton(title: "JSON 붙여넣기", systemImage: "doc.on.clipboard", action: pasteJSON)
                    actionButton(title: "JSON 복사", systemImage: "doc.on.doc", isDisabled: temporaryWords.isEmpty, action: copyJSON)
                }
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
                if isJSONImportEnabled {
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
                }

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
            if isJSONImportEnabled {
                importJSONFromClipboard(showAlerts: false)
            }
            return
        }

        if isJSONImportEnabled, english.looksLikeJSONArray {
            if importJSON(from: english) {
                inputWord = ""
                isInputFocused = true
            }
            return
        }

        addEnglishWord(english)
    }

    private func ensureAvailableEntryMode() {
        if !isJSONImportEnabled {
            entryMode = .manual
        }
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

private struct AddWordsHelpView: View {
    @State private var isPromptCopied = false

    private let jsonPrompt = """
    아래 영단어 목록을 VocaDay에서 가져올 수 있는 JSON 배열로 만들어줘.

    규칙:
    - 설명이나 마크다운 없이 JSON 배열만 출력해줘.
    - 각 항목은 english, meaningKo, exampleEn, exampleKo, note, toeicTag 키를 모두 포함해줘.
    - meaningKo에는 자연스러운 한국어 뜻을 넣어줘.
    - exampleEn에는 해당 단어를 사용한 자연스러운 영어 예문을 넣어줘.
    - exampleKo에는 영어 예문의 자연스러운 한국어 번역을 넣어줘.
    - note에는 암기에 도움이 되는 짧은 설명을 넣어줘.
    - toeicTag에는 품사 또는 TOEIC 관련 분류를 짧게 넣어줘.
    - 값이 없으면 빈 문자열을 사용해줘.

    영단어 목록:
    [여기에 영단어를 붙여넣기]
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                helpSection(
                    title: "JSON 모드란?",
                    systemImage: "curlybraces.square"
                ) {
                    Text("여러 단어의 뜻, 예문, 메모와 태그를 한 번에 가져오는 고급 입력 방식입니다. 직접 입력만 사용할 때는 켜지 않아도 됩니다.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                helpSection(
                    title: "JSON 모드 켜기",
                    systemImage: "gearshape"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        helpStep(number: 1, text: "왼쪽 메뉴에서 설정을 여세요.")
                        helpStep(number: 2, text: "고급 기능에서 ‘JSON 기능 사용’을 켜세요.")
                        helpStep(number: 3, text: "단어 추가로 돌아와 ‘JSON 가져오기’를 선택하세요.")
                        helpStep(number: 4, text: "JSON을 붙여넣고 목록을 확인한 뒤 데이에 저장하세요.")
                    }
                }

                helpSection(
                    title: "AI에게 요청할 프롬프트",
                    systemImage: "sparkles"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("아래 상자를 누르면 프롬프트 전체가 복사됩니다. 마지막 줄에 원하는 영단어를 넣어 AI에게 보내세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(action: copyPrompt) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label(
                                        isPromptCopied ? "복사됨" : "눌러서 복사",
                                        systemImage: isPromptCopied ? "checkmark.circle.fill" : "doc.on.doc"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isPromptCopied ? Color.green : Color.accentColor)

                                    Spacer()
                                }

                                Text(jsonPrompt)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("JSON 생성 프롬프트 복사")
                        .accessibilityHint("프롬프트 전체를 클립보드에 복사합니다")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("단어 추가 도움말")
    }

    private func helpSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            content()
        }
        .padding(18)
        .calmCard()
    }

    private func helpStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())

            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyPrompt() {
        ClipboardService.copyText(jsonPrompt)

        withAnimation(.easeInOut(duration: 0.18)) {
            isPromptCopied = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.18)) {
                isPromptCopied = false
            }
        }
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
