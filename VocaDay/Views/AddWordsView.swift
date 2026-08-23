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
    @AppStorage("hasDismissedJSONAddWordsGuide") private var hasDismissedJSONAddWordsGuide = false
    @State private var inputWord = ""
    @State private var jsonInput = ""
    @State private var temporaryWords: [VocaWordJSON] = []
    @State private var selectedTemporaryWordID: UUID?
    @State private var alert: VocaAlert?
    @State private var pendingTranslations: [PendingTranslation] = []
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isShowingGuideDismissalConfirmation = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    entrySetupCard

                    if shouldShowUsageGuide {
                        usageGuide
                    }

                    entryInputCard

                    TemporaryWordTable(
                        words: $temporaryWords,
                        selectedWordID: $selectedTemporaryWordID,
                        emptyTitle: temporaryWordsEmptyTitle
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
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("확인"))
            )
        }
        .confirmationDialog(
            "이 안내 상자를 숨길까요?",
            isPresented: $isShowingGuideDismissalConfirmation,
            titleVisibility: .visible
        ) {
            Button("안내 숨기기", role: .destructive) {
                dismissCurrentUsageGuide()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 입력 방식에서는 다시 표시되지 않습니다. 오른쪽 위 ? 도움말은 언제든 열 수 있습니다.")
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

    private var entrySetupCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            selectedDayPicker

            Divider()

            entryModeSection
        }
        .padding(18)
        .calmCard()
        .onboardingSpotlight(.addMode)
    }

    private var selectedDayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1. 저장할 데이", systemImage: "calendar")
                .font(.headline)

            Text("아래에서 준비한 단어는 마지막에 선택한 데이로 저장됩니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                if days.isEmpty {
                    Button {
                        let day = DayFactory.createNextDay(existingDays: days, in: modelContext)
                        selectedDayID = day.id
                    } label: {
                        Label("첫 데이 만들기", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Picker("저장할 데이", selection: $selectedDayID) {
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
    }

    private var entryModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("2. 입력 방법", systemImage: "square.and.pencil")
                .font(.headline)

            if isJSONImportEnabled {
                Picker("입력 방법", selection: $entryMode) {
                    ForEach(AddEntryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(entryModeDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isJSONImportEnabled, entryMode == .json {
                Label("VocaDay가 AI를 실행하는 기능이 아닙니다. 외부 AI에서 만든 결과를 복사해 오는 방식입니다.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var usageGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label(usageGuideTitle, systemImage: "lightbulb.fill")
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

            if isJSONImportEnabled, entryMode == .json {
                NavigationLink {
                    AddWordsHelpView()
                } label: {
                    Label("외부 AI 사용법과 복사용 프롬프트 보기", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
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
                ("프롬프트 준비", "오른쪽 위 ?에서 입력·출력 예시가 포함된 프롬프트를 복사해 외부 AI 입력창에 붙여넣으세요."),
                ("영단어 JSON 준비", "직접 입력으로 단어들을 임시 목록에 넣고 아래 ‘AI용 영단어 JSON 복사’를 누르세요."),
                ("외부 AI에 보내기", "복사한 영단어 JSON을 프롬프트의 ‘변환할 입력 JSON’ 자리에 붙여넣고 외부 AI에 보내세요."),
                ("완성 JSON 가져오기", "외부 AI 답변을 복사한 뒤 아래에 붙여넣고 ‘임시 목록으로 가져오기’를 누르세요."),
                ("확인 후 저장", "뜻과 메모를 직접 고친 뒤 ‘선택한 데이에 저장’을 누르세요.")
            ]
        }

        return [
            ("데이 선택", "완성된 단어를 저장할 데이를 먼저 고르세요."),
            ("영단어 입력", "영단어 또는 구문을 한 개 입력하고 키보드의 완료 또는 Return/Enter를 누르세요."),
            ("뜻 확인·수정", "기기의 번역 기능이 한국어 뜻을 채웁니다. 처음에는 번역 언어 다운로드 안내가 나올 수 있습니다."),
            ("데이에 저장", "표의 셀을 눌러 내용을 고친 뒤 ‘선택한 데이에 저장’을 누르세요.")
        ]
    }

    private var usageGuideTitle: String {
        isJSONImportEnabled && entryMode == .json ? "외부 AI로 단어 가져오는 순서" : "직접 단어 추가하는 순서"
    }

    private var entryModeDescription: String {
        if isJSONImportEnabled, entryMode == .json {
            return "여러 단어의 뜻과 예문을 외부 AI에서 JSON 형식으로 만든 뒤 한 번에 가져옵니다."
        }

        return "영단어를 한 개씩 입력합니다. 기기의 번역 기능이 한국어 뜻을 채우며, 저장 전에 직접 수정할 수 있습니다."
    }

    private var shouldShowUsageGuide: Bool {
        if isJSONImportEnabled, entryMode == .json {
            return !hasDismissedJSONAddWordsGuide
        }

        return !hasDismissedAddWordsGuide
    }

    private var temporaryWordsEmptyTitle: String {
        if isJSONImportEnabled, entryMode == .json {
            return "가져온 단어가 아직 없습니다. 위에 JSON을 붙여넣고 ‘임시 목록으로 가져오기’를 누르세요."
        }

        return "추가할 단어가 아직 없습니다. 위 입력란에 영단어를 입력하세요."
    }

    private func dismissCurrentUsageGuide() {
        if isJSONImportEnabled, entryMode == .json {
            hasDismissedJSONAddWordsGuide = true
        } else {
            hasDismissedAddWordsGuide = true
        }
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
                Label("외부 AI의 답변 붙여넣기", systemImage: "curlybraces.square")
                    .font(.headline)

                Spacer()

                Button("클립보드에서 붙여넣기") {
                    pasteJSONIntoEditor()
                }
                .buttonStyle(.bordered)
            }

            Text("외부 AI 앱이나 웹사이트에서 복사한 JSON 답변을 아래에 붙여넣으세요. 아직 답변이 없다면 오른쪽 위 ?에서 만드는 방법과 프롬프트를 확인하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if jsonInput.isEmpty {
                    Text("[ 로 시작하고 ] 로 끝나는 외부 AI의 JSON 답변")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $jsonInput)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled()
            }
            .frame(minHeight: 180)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                importJSONFromEditor()
            } label: {
                Label("임시 목록으로 가져오기", systemImage: "square.and.arrow.down")
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
            VStack(spacing: 10) {
                if isJSONImportEnabled {
                    actionButton(
                        title: "AI용 영단어 JSON 복사",
                        systemImage: "doc.on.doc",
                        isDisabled: temporaryWords.isEmpty,
                        action: copyTemporaryWordsAsJSON
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    actionButton(title: "선택 단어 삭제", systemImage: "trash", role: .destructive, isDisabled: selectedTemporaryWordID == nil) {
                        deleteSelectedTemporaryWord()
                        isInputFocused = true
                    }
                    actionButton(title: "선택한 데이에 저장", systemImage: "tray.and.arrow.down", isProminent: true, isDisabled: temporaryWords.isEmpty, action: saveToDay)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            #else
            HStack(spacing: 20) {
                if isJSONImportEnabled {
                    Button(action: copyTemporaryWordsAsJSON) {
                        Label("AI용 영단어 JSON 복사", systemImage: "doc.on.doc")
                            .frame(minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(temporaryWords.isEmpty)
                    .accessibilityLabel("AI용 영단어 JSON 복사")
                    .help("저장 전 확인 목록의 영단어만 AI 입력용 JSON으로 복사")
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    deleteSelectedTemporaryWord()
                    isInputFocused = true
                } label: {
                    Label("선택 단어 삭제", systemImage: "trash")
                        .frame(minHeight: 42)
                }
                .buttonStyle(.bordered)
                .disabled(selectedTemporaryWordID == nil)
                .accessibilityLabel("선택 단어 삭제")
                .help("선택 단어 삭제")

                Button {
                    saveToDay()
                } label: {
                    Label("선택한 데이에 저장", systemImage: "tray.and.arrow.down")
                        .frame(minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(temporaryWords.isEmpty)
                .accessibilityLabel("선택한 데이에 저장")
                .help("선택한 데이에 저장")
            }
            .font(.subheadline.weight(.semibold))
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
        guard !english.isEmpty else { return }

        addEnglishWord(english)
    }

    private func copyTemporaryWordsAsJSON() {
        guard !temporaryWords.isEmpty else {
            alert = VocaAlert(
                title: "복사할 단어가 없습니다",
                message: "먼저 직접 입력하거나 JSON을 가져와 저장 전 확인 목록에 단어를 추가하세요."
            )
            return
        }

        do {
            let englishOnlyWords = temporaryWords.map { word in
                VocaWordJSON(english: word.english)
            }
            let json = try JSONWordParser.encode(englishOnlyWords)
            ClipboardService.copyText(json)
            let countText = temporaryWords.count == 1 ? "단어 1개" : "단어 \(temporaryWords.count)개"
            alert = VocaAlert(
                title: "AI용 JSON을 복사했습니다",
                message: "저장 전 확인 목록의 \(countText)를 영단어만 채운 JSON으로 복사했습니다. 도움말의 프롬프트에서 ‘변환할 입력 JSON’ 자리에 붙여넣으세요."
            )
        } catch {
            alert = VocaAlert(
                title: "JSON을 복사하지 못했습니다",
                message: "잠시 후 다시 시도하세요."
            )
        }
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
        guard temporaryWords[index].meaningKo == "(번역 중...)" else { return }
        temporaryWords[index].meaningKo = meaningKo
    }

    private func pasteJSONIntoEditor() {
        guard let text = ClipboardService.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alert = VocaAlert(
                title: "복사한 내용이 없습니다",
                message: "먼저 ChatGPT 같은 외부 AI에서 JSON 답변을 복사한 뒤 다시 눌러주세요. 만드는 방법은 오른쪽 위 ?에서 볼 수 있습니다."
            )
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
    private func importJSON(from text: String, showAlerts: Bool = true) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if showAlerts {
                alert = VocaAlert(title: "JSON 비어 있음", message: "가져오기 전에 JSON 배열을 붙여넣으세요.")
            }
            return false
        }

        do {
            let decodedWords = try JSONWordParser.decode(text)
            guard !decodedWords.isEmpty else {
                if showAlerts {
                    alert = VocaAlert(
                        title: "가져올 단어가 없습니다",
                        message: "JSON 안의 english 값에 영단어가 들어 있는지 확인하세요. 오른쪽 위 ?에서 올바른 예시를 볼 수 있습니다."
                    )
                }
                return false
            }
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
                    ? "단어 1개를 저장 전 확인 목록에 넣었습니다. 내용을 수정한 뒤 선택한 데이에 저장하세요."
                    : "단어 \(decodedWords.count)개를 저장 전 확인 목록에 넣었습니다. 내용을 수정한 뒤 선택한 데이에 저장하세요."
                alert = VocaAlert(title: "단어를 가져왔습니다", message: message)
            }
            return true
        } catch {
            if showAlerts {
                alert = VocaAlert(
                    title: "JSON 형식을 읽을 수 없습니다",
                    message: "외부 AI 답변에서 [ 로 시작해 ] 로 끝나는 단어 배열을 복사했는지 확인하세요. 오른쪽 위 ?에서 복사용 프롬프트와 올바른 예시를 볼 수 있습니다."
                )
            }
            return false
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

        guard validateTemporaryWordsForSave() else { return }

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

    private func validateTemporaryWordsForSave() -> Bool {
        let emptyWordNumbers = temporaryWords.enumerated().compactMap { index, word in
            word.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? index + 1 : nil
        }
        if !emptyWordNumbers.isEmpty {
            alert = VocaAlert(
                title: "영단어를 입력하세요",
                message: "저장 전 확인 목록의 \(emptyWordNumbers.map(String.init).joined(separator: ", "))번 행에 영단어가 없습니다. 영단어를 입력하거나 해당 행을 삭제하세요."
            )
            return false
        }

        let groupedWords = Dictionary(grouping: temporaryWords, by: { $0.english.normalizedEnglish })
        let duplicates = groupedWords
            .filter { $0.value.count > 1 }
            .compactMap { $0.value.first?.english }
            .sorted()
        if !duplicates.isEmpty {
            alert = VocaAlert(
                title: "중복된 영단어가 있습니다",
                message: "\(duplicates.joined(separator: ", "))이(가) 목록에 두 번 이상 있습니다. 하나만 남긴 뒤 저장하세요."
            )
            return false
        }

        return true
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
    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @State private var isPromptCopied = false

    private let jsonPrompt = """
    아래 입력 JSON의 영단어를 VocaDay 앱에서 가져올 수 있는 완성된 JSON 배열로 만들어줘.

    규칙:
    - 설명, 제목, ``` 표시 없이 JSON 배열만 출력해줘.
    - 각 항목은 english, meaningKo, exampleEn, exampleKo, note, toeicTag 키를 모두 포함해줘.
    - 모든 값은 문자열로 작성해줘.
    - meaningKo에는 자연스러운 한국어 뜻을 넣어줘.
    - exampleEn에는 해당 단어를 사용한 자연스러운 영어 예문을 넣어줘.
    - exampleKo에는 영어 예문의 자연스러운 한국어 번역을 넣어줘.
    - note에는 암기에 도움이 되는 짧은 설명을 넣어줘.
    - toeicTag에는 품사 또는 TOEIC 관련 분류를 짧게 넣어줘.
    - 값이 없으면 빈 문자열을 사용해줘.
    - 같은 영단어를 중복해서 만들지 마.

    입력 JSON 예시:
    [
      {
        "english": "acquire",
        "meaningKo": "",
        "exampleEn": "",
        "exampleKo": "",
        "note": "",
        "toeicTag": ""
      }
    ]

    출력 JSON 예시:
    [
      {
        "english": "acquire",
        "meaningKo": "습득하다, 얻다",
        "exampleEn": "She acquired new skills at work.",
        "exampleKo": "그녀는 직장에서 새로운 기술을 습득했다.",
        "note": "노력해서 지식이나 능력을 얻을 때 자주 사용",
        "toeicTag": "동사"
      }
    ]

    변환할 입력 JSON:
    [여기에 VocaDay의 ‘AI용 영단어 JSON 복사’로 복사한 JSON을 붙여넣기]
    """

    private let jsonExample = """
    [
      {
        "english": "acquire",
        "meaningKo": "습득하다, 얻다",
        "exampleEn": "She acquired new skills at work.",
        "exampleKo": "그녀는 직장에서 새로운 기술을 습득했다.",
        "note": "노력해서 지식이나 능력을 얻을 때 자주 사용",
        "toeicTag": "동사"
      }
    ]
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                importantNotice

                helpSection(
                    title: "직접 입력으로 추가하기",
                    systemImage: "square.and.pencil"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        helpStep(number: 1, text: "‘추가’ 화면 위에서 저장할 데이를 선택하세요.")
                        helpStep(number: 2, text: "영단어 또는 짧은 구문을 한 개 입력하고 키보드의 완료 또는 Return/Enter를 누르세요.")
                        helpStep(number: 3, text: "기기의 번역 기능이 한국어 뜻을 채울 때까지 잠시 기다리세요. 처음에는 번역 언어 다운로드 안내가 나올 수 있습니다.")
                        helpStep(number: 4, text: "저장 전 확인 표에서 뜻·메모·태그를 직접 고친 뒤 ‘선택한 데이에 저장’을 누르세요.")
                    }
                }

                helpSection(
                    title: "JSON은 무엇인가요?",
                    systemImage: "curlybraces.square"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("JSON은 영단어, 한국어 뜻, 예문, 메모를 정해진 항목으로 묶은 텍스트 형식입니다. 여러 단어를 한 번에 가져오고 싶을 때만 사용하면 됩니다.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Label("직접 입력만 사용할 사람은 JSON 기능을 켤 필요가 없습니다.", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))

                        Label(
                            isJSONImportEnabled ? "현재 JSON 가져오기가 켜져 있습니다." : "현재 JSON 가져오기가 꺼져 있습니다.",
                            systemImage: isJSONImportEnabled ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(isJSONImportEnabled ? Color.green : .secondary)
                    }
                }

                helpSection(
                    title: "외부 AI로 여러 단어 가져오기",
                    systemImage: "arrow.left.arrow.right"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        helpStep(number: 1, text: "\(settingsLocation)에서 ‘외부 AI의 JSON 단어 가져오기’를 켜세요.")
                        helpStep(number: 2, text: "이 페이지 아래의 프롬프트 상자를 눌러 복사하고, 외부 AI 입력창에 먼저 붙여넣으세요.")
                        helpStep(number: 3, text: "VocaDay의 ‘직접 입력’에서 원하는 영단어를 하나씩 입력하고 완료 또는 Return/Enter를 눌러 임시 목록에 추가하세요.")
                        helpStep(number: 4, text: "화면 아래의 ‘AI용 영단어 JSON 복사’를 눌러 임시 목록의 영단어 JSON을 복사하세요.")
                        helpStep(number: 5, text: "외부 AI 입력창으로 돌아가 프롬프트 마지막의 ‘변환할 입력 JSON’ 자리에 복사한 JSON을 붙여넣고 전송하세요.")
                        helpStep(number: 6, text: "외부 AI가 만든 [ 로 시작해 ] 로 끝나는 완성 JSON 답변 전체를 복사하세요.")
                        helpStep(number: 7, text: "VocaDay의 ‘추가’로 돌아와 ‘JSON 가져오기’를 선택하고 ‘클립보드에서 붙여넣기’를 누르세요.")
                        helpStep(number: 8, text: "‘임시 목록으로 가져오기’를 누른 뒤 내용을 확인·수정하고 선택한 데이에 저장하세요.")
                    }
                }

                helpSection(
                    title: "AI 입력용 영단어 JSON 복사하기",
                    systemImage: "doc.on.doc"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("저장 전 확인 목록에 단어가 있으면 화면 아래의 ‘AI용 영단어 JSON 복사’를 눌러 외부 AI에 보낼 입력 JSON을 만들 수 있습니다.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        troubleshootingItem("임시 목록의 영단어만 유지되고, 뜻·예문·메모·태그는 외부 AI가 채울 수 있도록 빈 문자열로 복사됩니다.")
                        troubleshootingItem("복사한 JSON은 프롬프트 마지막의 ‘변환할 입력 JSON’ 자리에 붙여넣으세요.")
                        troubleshootingItem("이 버튼은 설정에서 ‘외부 AI의 JSON 단어 가져오기’를 켰을 때만 표시됩니다.")
                    }
                }

                helpSection(
                    title: "외부 AI 사용 시 알아두기",
                    systemImage: "hand.raised"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("VocaDay 안에는 AI가 내장되어 있지 않습니다.", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("VocaDay는 외부 AI를 자동으로 열거나, 단어를 보내거나, 답변을 받아오지 않습니다. 사용자가 외부 AI에서 직접 생성하고 복사한 결과만 VocaDay에 붙여넣습니다.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("외부 AI에 입력한 내용은 해당 AI 서비스의 개인정보 처리방침을 따릅니다. 개인정보나 민감한 내용은 프롬프트에 넣지 마세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                helpSection(
                    title: "외부 AI에 보낼 프롬프트",
                    systemImage: "sparkles"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("아래 상자를 누르면 입력 JSON 예시와 출력 JSON 예시가 포함된 프롬프트 전체가 복사됩니다. 외부 AI 입력창에 붙여넣은 뒤, 마지막 ‘변환할 입력 JSON’ 자리를 VocaDay에서 복사한 영단어 JSON으로 바꾸세요.")
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

                helpSection(
                    title: "올바른 결과 예시",
                    systemImage: "checkmark.square"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("외부 AI의 답변은 아래처럼 [ 로 시작하고 ] 로 끝나야 합니다. 항목이 여러 개라면 { } 묶음이 쉼표로 이어집니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(jsonExample)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                helpSection(
                    title: "가져오기가 안 될 때",
                    systemImage: "wrench.and.screwdriver"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        troubleshootingItem("외부 AI 답변에서 [ 부터 마지막 ] 까지가 포함되었는지 확인하세요.")
                        troubleshootingItem("각 단어에 english 값이 있고 빈칸이 아닌지 확인하세요.")
                        troubleshootingItem("AI의 설명 문장이 함께 있어도 배열 부분은 자동으로 찾아 읽지만, 결과 예시와 같은 형식이 가장 안전합니다.")
                        troubleshootingItem("가져온 뒤 뜻이나 메모가 마음에 들지 않으면 저장 전 확인 표에서 바로 수정하세요.")
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

    private var importantNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("중요: AI는 VocaDay 밖에서 사용합니다", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text("VocaDay는 단어를 저장하고 복습하는 앱입니다. AI로 단어 정보 생성을 원하면 별도의 AI 앱이나 웹사이트를 직접 사용해야 합니다.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        }
    }

    private var settingsLocation: String {
        return "‘데이’ 화면 오른쪽 위 설정"
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

    private func troubleshootingItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 1)
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
}

#Preview {
    NavigationStack {
        AddWordsView(selectedDayID: .constant(nil), quickAddWord: .constant(nil), entryMode: .constant(.manual))
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
