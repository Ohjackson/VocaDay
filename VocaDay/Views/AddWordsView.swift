import SwiftData
import SwiftUI

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
    private let wordGenerationService: any EnglishWordGenerating
    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @AppStorage("hasDismissedAddWordsGuide") private var hasDismissedAddWordsGuide = false
    @AppStorage("hasDismissedJSONAddWordsGuide") private var hasDismissedJSONAddWordsGuide = false
    @AppStorage("hasAcknowledgedAppleIntelligenceWordGeneration") private var hasAcknowledgedAppleIntelligence = false
    @AppStorage("isAppleIntelligenceWordGenerationEnabled") private var isAppleIntelligenceWordGenerationEnabled = true
    @State private var inputWord = ""
    @State private var jsonInput = ""
    @State private var temporaryWords: [VocaWordJSON] = []
    @State private var selectedTemporaryWordID: UUID?
    @State private var alert: VocaAlert?
    @State private var isGeneratingWord = false
    @State private var generationTask: Task<Void, Never>?
    @State private var isShowingGuideDismissalConfirmation = false
    /// 예문 문제로 빈칸 문제를 못 만드는 단어가 있을 때 저장 전 확인.
    @State private var dataWarningMessage: String?
    @State private var isShowingNewDayAlert = false
    @State private var isShowingAppleIntelligenceDisclosure = false
    @State private var newDayTitle = ""
    @FocusState private var isInputFocused: Bool

    init(
        selectedDayID: Binding<UUID?>,
        quickAddWord: Binding<String?>,
        entryMode: Binding<AddEntryMode>,
        wordGenerationService: any EnglishWordGenerating = AppleFoundationWordGenerationService()
    ) {
        _selectedDayID = selectedDayID
        _quickAddWord = quickAddWord
        _entryMode = entryMode
        self.wordGenerationService = wordGenerationService
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    entrySetupCard
                        .componentSpotlight(.storageSelection)

                    if shouldShowUsageGuide {
                        usageGuide
                            .componentSpotlight(.addGuide)
                    }

                    entryInputCard
                        .componentSpotlight(.wordInput)

                    TemporaryWordTable(
                        words: $temporaryWords,
                        selectedWordID: $selectedTemporaryWordID,
                        emptyTitle: temporaryWordsEmptyTitle
                    )
                    .componentSpotlight(.pendingWords)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

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
        .alert("Apple Intelligence 사용 안내", isPresented: $isShowingAppleIntelligenceDisclosure) {
            Button("수동으로 추가") {
                addManualInputWord()
            }
            Button("동의하고 생성") {
                hasAcknowledgedAppleIntelligence = true
                startGeneratingInputWord()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("입력한 영단어는 Apple의 온디바이스 모델이 이 기기 안에서 처리하며 외부 AI 서비스로 전송되지 않습니다. iPhone에서는 15 Pro·15 Pro Max 및 이후 Apple Intelligence 지원 모델에서 사용할 수 있습니다.")
        }
        .confirmationDialog(
            "이 안내 상자를 숨길까요?",
            isPresented: $isShowingGuideDismissalConfirmation,
            titleVisibility: .visible
        ) {
            Button("안내 숨기기") {
                dismissCurrentUsageGuide()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 입력 방식에서는 다시 표시되지 않습니다. 오른쪽 위 ? 도움말은 언제든 열 수 있습니다.")
        }
        .confirmationDialog(
            "예문을 보완할까요?",
            isPresented: Binding(
                get: { dataWarningMessage != nil },
                set: { if !$0 { dataWarningMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("그대로 저장") {
                dataWarningMessage = nil
                saveAfterDataCheck()
            }
            Button("예문 고치기", role: .cancel) {
                dataWarningMessage = nil
            }
        } message: {
            Text(dataWarningMessage ?? "")
        }
        .alert("새 데이", isPresented: $isShowingNewDayAlert) {
            TextField("데이 이름", text: $newDayTitle)

            Button("취소", role: .cancel) {
                newDayTitle = ""
            }

            Button("만들기", action: createAndSelectNewDay)
                .disabled(newDayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("새 데이의 이름을 입력하세요. 만든 데이는 저장 위치로 자동 선택됩니다.")
        }
        .onAppear {
            ensureAvailableEntryMode()
            ensureSelectedDay()
            consumeQuickAddWord()
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
        .onDisappear {
            generationTask?.cancel()
        }
    }

    private var entrySetupCard: some View {
        AddWordsSetupCard(
            destinations: days.map { DayDestinationOption(id: $0.id, title: $0.title) },
            selectedDestinationID: $selectedDayID,
            showsEntryMode: isJSONImportEnabled,
            entryMode: $entryMode,
            onCreateDestination: presentNewDayAlert
        )
    }

    private func presentNewDayAlert() {
        newDayTitle = DayFactory.nextDayTitle(existingDays: days)
        isShowingNewDayAlert = true
    }

    private func createAndSelectNewDay() {
        let title = newDayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let day = DayFactory.createDay(title: title, in: modelContext)
        if let error = modelContext.saveReportingError() {
            alert = .saveFailure(error)
            return
        }
        selectedDayID = day.id
        newDayTitle = ""
    }

    private var usageGuide: some View {
        AddWordsGuideCard(
            title: usageGuideTitle,
            message: usageGuideMessage,
            systemImage: entryMode == .json ? "curlybraces" : "return",
            showsHelpLink: isJSONImportEnabled && entryMode == .json,
            onDismiss: { isShowingGuideDismissalConfirmation = true }
        )
    }

    private var helpNavigationLink: some View {
        NavigationLink(value: AppRoute.addWordsHelp) {
            Image(systemName: "questionmark.circle")
        }
        .componentSpotlight(.addHelpButton)
        .accessibilityLabel("단어 추가 도움말")
        .help("단어 추가 도움말")
    }

    private var usageGuideTitle: String {
        isJSONImportEnabled && entryMode == .json ? "영단어를 모으거나 완성 JSON을 붙여넣으세요" : "영단어를 입력하고 Enter를 누르세요"
    }

    private var usageGuideMessage: String {
        if isJSONImportEnabled, entryMode == .json {
            return "모은 영단어는 아래에서 JSON으로 복사할 수 있습니다. AI는 VocaDay 밖에서 사용합니다."
        }

        if generationAvailability.isAvailable {
            return "Enter를 누르면 빈 수동 입력 항목이 추가됩니다. 뜻과 예문을 자동으로 채우려면 AI로 생성 버튼을 따로 누르세요."
        }

        return "Enter를 누르면 수동 입력 항목이 추가됩니다. 뜻과 예문을 직접 채운 뒤 저장하세요."
    }

    private var shouldShowUsageGuide: Bool {
        if isJSONImportEnabled, entryMode == .json {
            return !hasDismissedJSONAddWordsGuide
        }

        return !hasDismissedAddWordsGuide
    }

    private var temporaryWordsEmptyTitle: String {
        if isJSONImportEnabled, entryMode == .json {
            return "아직 가져온 단어가 없습니다. JSON을 붙여넣고 목록으로 변환하세요."
        }

        return "아직 추가할 단어가 없습니다. 위 입력란에서 시작하세요."
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
            VStack(spacing: 16) {
                WordInputCard(
                    title: "영단어 모으기",
                    inputWord: $inputWord,
                    isInputFocused: $isInputFocused,
                    onSubmit: addRawInputWord
                )
                jsonInputCard
            }
        } else {
            WordInputCard(
                inputWord: $inputWord,
                isInputFocused: $isInputFocused,
                submitHint: "Enter로 수동 추가",
                isProcessing: isGeneratingWord,
                primaryActionTitle: generationAvailability.isAvailable ? "AI로 생성" : nil,
                onPrimaryAction: requestAIGeneration,
                onSubmit: addManualInputWord
            )
        }
    }

    private var jsonInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("완성 JSON 붙여넣기", systemImage: "curlybraces.square")
                    .font(.headline)

                Spacer()

                Button {
                    pasteJSONIntoEditor()
                } label: {
                    Label("붙여넣기", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }

            Text("외부 AI에서 복사한 JSON 배열을 붙여넣으세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if jsonInput.isEmpty {
                    Text("[ 로 시작하고 ] 로 끝나는 JSON 배열")
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
            .frame(minHeight: 150)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                importJSONFromEditor()
            } label: {
                Label("JSON을 목록으로 변환", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(jsonInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .calmCard()
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()

            #if os(iOS)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    if shouldShowAICopyButton {
                        actionButton(
                            title: "영단어 JSON 복사",
                            systemImage: "doc.on.doc",
                            isDisabled: temporaryWords.isEmpty,
                            action: copyTemporaryWordsAsJSON
                        )
                    }

                    actionButton(
                        title: saveButtonTitle,
                        systemImage: "tray.and.arrow.down",
                        isProminent: true,
                        isDisabled: isSaveDisabled,
                        action: saveToDay
                    )
                }

                VStack(spacing: 8) {
                    if shouldShowAICopyButton {
                        actionButton(
                            title: "영단어 JSON 복사",
                            systemImage: "doc.on.doc",
                            isDisabled: temporaryWords.isEmpty,
                            action: copyTemporaryWordsAsJSON
                        )
                    }

                    actionButton(
                        title: saveButtonTitle,
                        systemImage: "tray.and.arrow.down",
                        isProminent: true,
                        isDisabled: isSaveDisabled,
                        action: saveToDay
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            #else
            HStack(spacing: 12) {
                if shouldShowAICopyButton {
                    Button(action: copyTemporaryWordsAsJSON) {
                        Label("영단어 JSON 복사", systemImage: "doc.on.doc")
                            .frame(minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(temporaryWords.isEmpty)
                    .accessibilityLabel("영단어 JSON 복사")
                    .help("저장 전 확인 목록의 영단어만 AI 입력용 JSON으로 복사")
                }

                Spacer(minLength: 0)

                Button {
                    saveToDay()
                } label: {
                    Label(saveButtonTitle, systemImage: "tray.and.arrow.down")
                        .frame(minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
                .accessibilityLabel(saveButtonTitle)
                .help(saveButtonTitle)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            #endif
        }
        .background(.regularMaterial)
    }

    private var shouldShowAICopyButton: Bool {
        isJSONImportEnabled && entryMode == .json
    }

    private var generationAvailability: EnglishWordGenerationAvailability {
        guard isAppleIntelligenceWordGenerationEnabled else {
            return .unavailable(.disabledInSettings)
        }
        return wordGenerationService.availability
    }

    private var isSaveDisabled: Bool {
        temporaryWords.isEmpty || isGeneratingWord || selectedDay == nil
    }

    private var saveButtonTitle: String {
        if isGeneratingWord {
            return "AI 학습 데이터 생성 중"
        }

        let destination = selectedDay?.title ?? "데이"
        guard !temporaryWords.isEmpty else { return "\(destination)에 저장" }
        return "\(destination)에 \(temporaryWords.count)개 저장"
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
        AppActionButton(
            title: title,
            systemImage: systemImage,
            role: role,
            isProminent: isProminent,
            isDisabled: isDisabled,
            action: action
        )
        .componentSpotlight(isProminent ? .saveWordsButton : .navigation)
    }

    private func requestAIGeneration() {
        guard generationAvailability.isAvailable else {
            addManualInputWord()
            return
        }

        guard hasAcknowledgedAppleIntelligence else {
            isShowingAppleIntelligenceDisclosure = true
            return
        }

        startGeneratingInputWord()
    }

    private func addRawInputWord() {
        guard let english = validatedInputWord() else { return }
        appendManualDraft(english)
    }

    private func addManualInputWord() {
        guard let english = validatedInputWord() else { return }
        appendManualDraft(english)
    }

    private func startGeneratingInputWord() {
        guard !isGeneratingWord, let english = validatedInputWord() else { return }

        guard generationAvailability.isAvailable else {
            alert = VocaAlert(title: "AI 자동 생성 사용 불가", message: generationAvailability.statusMessage)
            return
        }

        isGeneratingWord = true
        isInputFocused = false
        generationTask?.cancel()
        generationTask = Task {
            do {
                let generated = try await wordGenerationService.generateWord(for: english)
                try Task.checkCancellation()
                await MainActor.run {
                    let draft = GeneratedWordDraftMapper.makeDraft(from: generated)
                    temporaryWords.insert(draft, at: 0)
                    selectedTemporaryWordID = draft.id
                    inputWord = ""
                    isGeneratingWord = false
                    isInputFocused = true
                }
            } catch is CancellationError {
                await MainActor.run {
                    isGeneratingWord = false
                }
            } catch {
                await MainActor.run {
                    isGeneratingWord = false
                    alert = VocaAlert(
                        title: "AI 학습 데이터 생성 실패",
                        message: (error as? LocalizedError)?.errorDescription
                            ?? "다시 시도하거나 직접 추가를 사용하세요."
                    )
                    isInputFocused = true
                }
            }
        }
    }

    private func validatedInputWord() -> String? {
        do {
            let english = try EnglishWordInputValidator.validate(inputWord)
            guard validateDuplicate(english) else { return nil }
            return english
        } catch {
            alert = VocaAlert(
                title: "영단어를 확인하세요",
                message: (error as? LocalizedError)?.errorDescription ?? "영어 단어 하나만 입력하세요."
            )
            return nil
        }
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

    private func validateDuplicate(_ english: String) -> Bool {
        guard !temporaryWords.contains(where: { $0.english.normalizedEnglish == english.normalizedEnglish }) else {
            alert = VocaAlert(
                title: "중복 단어",
                message: "\"\(english)\"은(는) 이미 저장 전 목록에 있습니다."
            )
            isInputFocused = true
            return false
        }

        if let duplicateLocation = existingWordLocation(forNormalizedEnglish: english.normalizedEnglish) {
            alert = VocaAlert(
                title: "중복 단어",
                message: "\"\(english)\"은(는) 이미 \(duplicateLocation.dayTitles.joined(separator: ", "))에 있습니다."
            )
            isInputFocused = true
            return false
        }

        return true
    }

    private func appendManualDraft(_ english: String) {
        let word = VocaWordJSON(english: english)
        temporaryWords.insert(word, at: 0)
        selectedTemporaryWordID = word.id
        inputWord = ""
        isInputFocused = true
    }

    private func consumeQuickAddWord() {
        guard let word = quickAddWord?.trimmingCharacters(in: .whitespacesAndNewlines),
              !word.isEmpty else {
            return
        }

        quickAddWord = nil
        inputWord = word
        if let validated = validatedInputWord() {
            appendManualDraft(validated)
        }
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
                    ? "단어 1개를 저장 전 목록에 넣었습니다. 내용을 확인한 뒤 저장하세요."
                    : "단어 \(decodedWords.count)개를 저장 전 목록에 넣었습니다. 내용을 확인한 뒤 저장하세요."
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
        guard validateStudyData() else { return }
        saveAfterDataCheck()
    }

    /// 뜻이 없는 단어는 저장하지 않는다. 예문이 부족한 단어는 무엇이 빠지는지 알리고 확인을 받는다.
    private func validateStudyData() -> Bool {
        let checks = temporaryWords.enumerated().map { ($0.offset + 1, $0.element, WordDataCheck.issues(for: $0.element)) }
        let missingMeaning = checks.filter { $0.2.contains(.missingMeaning) }
        if !missingMeaning.isEmpty {
            alert = VocaAlert(
                title: "한국어 뜻을 입력하세요",
                message: "\(missingMeaning.map { "\($0.0)번 \($0.1.english)" }.joined(separator: ", "))에 뜻이 없습니다. 뜻이 있어야 복습 카드와 시험 문제를 만들 수 있어요."
            )
            return false
        }
        let notReady = checks.filter { !WordDataCheck.isQuizReady($0.2) }
        if !notReady.isEmpty {
            dataWarningMessage = "\(notReady.map(\.1.english).joined(separator: ", "))은(는) 영어 예문에 단어가 없어 빈칸 고르기·빈칸 쓰기가 나오지 않아요. 단어가 들어간 예문으로 고치면 모든 문제 유형을 풀 수 있어요."
            return false
        }
        return true
    }

    private func saveAfterDataCheck() {
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

            let word = GeneratedWordDraftMapper.makeEntity(
                from: temporaryWord,
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
        guard let selectedDayID else { return days.last }
        return days.first { $0.id == selectedDayID } ?? days.last
    }

    private func ensureSelectedDay() {
        guard !days.isEmpty else {
            selectedDayID = nil
            return
        }

        if let selectedDayID, days.contains(where: { $0.id == selectedDayID }) {
            return
        }

        selectedDayID = days.last?.id
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

struct AddWordsHelpView: View {
    @AppStorage("isJSONImportEnabled") private var isJSONImportEnabled = false
    @State private var isPromptCopied = false

    private let jsonPrompt = """
    아래 입력 JSON의 영단어를 VocaDay 앱에서 가져올 수 있는 완성된 JSON 배열로 만들어줘.

    규칙:
    - 설명, 제목, ``` 표시 없이 JSON 배열만 출력해줘.
    - 각 항목은 english, meaningKo, exampleEn, exampleKo, note, toeicTag 키를 모두 포함해줘.
    - 모든 값은 문자열로 작성해줘.
    - meaningKo에는 품사 약어를 붙인 자연스러운 한국어 뜻을 넣어줘. 예: "v. 연기하다, 미루다" / "n. 결과; adj. 최종의"
    - exampleEn에는 자연스러운 영어 예문 한 문장을 넣어줘. 반드시 english 단어 자체(또는 -s, -ed, -ing 같은 활용형)를 그대로 한 번 포함해야 해. 동의어나 대명사로 바꾸지 마. 이 단어 자리가 빈칸 문제의 정답이 돼.
    - exampleKo에는 영어 예문의 자연스러운 한국어 번역을 반드시 넣어줘. 빈칸 문제의 힌트로 쓰여.
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
        "meaningKo": "v. 습득하다, 얻다",
        "exampleEn": "She acquired new skills at work.",
        "exampleKo": "그녀는 직장에서 새로운 기술을 습득했다.",
        "note": "노력해서 지식이나 능력을 얻을 때 자주 사용",
        "toeicTag": "동사"
      }
    ]

    변환할 입력 JSON:
    [여기에 VocaDay의 ‘AI용 JSON 복사’로 복사한 JSON을 붙여넣기]
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
                    title: "복습·시험에 필요한 단어 데이터",
                    systemImage: "checkmark.seal"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        helpStep(number: 1, text: "한국어 뜻: 짝 맞추기·뜻 고르기·복습 카드에 쓰여요. 없으면 저장할 수 없어요.")
                        helpStep(number: 2, text: "단어가 들어간 영어 예문: 예문 속 단어 자리가 빈칸 문제의 정답이 돼요. postponed처럼 활용형도 괜찮아요.")
                        helpStep(number: 3, text: "예문 번역: 빈칸 문제에서 뜻을 짐작하는 힌트로 보여 줘요.")
                        Text("저장 전 목록의 각 단어 아래에 준비 상태가 표시돼요. Apple Intelligence 생성과 JSON 프롬프트는 이 조건에 맞춰 예문을 만들어요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                helpSection(
                    title: "Apple Intelligence로 추가하기",
                    systemImage: "apple.intelligence"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        helpStep(number: 1, text: "‘추가’ 화면 위에서 저장할 데이를 선택하세요.")
                        helpStep(number: 2, text: "영어 단어 하나를 입력하고 ‘AI로 생성’ 또는 Return/Enter를 누르세요.")
                        helpStep(number: 3, text: "Apple의 온디바이스 모델이 자주 쓰는 뜻을 최대 3개까지 품사와 예문으로 정리합니다.")
                        helpStep(number: 4, text: "저장 전 목록에서 결과를 확인하고 필요한 부분을 고친 뒤 아래의 저장 버튼을 누르세요.")
                        helpStep(number: 5, text: "Apple Intelligence를 쓸 수 없는 기기에서는 ‘직접 추가’로 빈 항목을 만든 뒤 직접 입력할 수 있습니다.")
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
                        helpStep(number: 3, text: "VocaDay의 ‘직접 입력’에서 원하는 영단어를 하나씩 입력하고 완료 또는 Return/Enter를 눌러 저장 전 목록에 추가하세요.")
                        helpStep(number: 4, text: "화면 아래의 ‘AI용 JSON 복사’를 눌러 저장 전 목록의 영단어 JSON을 복사하세요.")
                        helpStep(number: 5, text: "외부 AI 입력창으로 돌아가 프롬프트 마지막의 ‘변환할 입력 JSON’ 자리에 복사한 JSON을 붙여넣고 전송하세요.")
                        helpStep(number: 6, text: "외부 AI가 만든 [ 로 시작해 ] 로 끝나는 완성 JSON 답변 전체를 복사하세요.")
                        helpStep(number: 7, text: "VocaDay의 ‘추가’로 돌아와 ‘JSON 가져오기’를 선택하고 ‘붙여넣기’를 누르세요.")
                        helpStep(number: 8, text: "‘JSON을 목록으로 변환’을 누른 뒤 내용을 확인·수정하고 저장하세요.")
                    }
                }

                helpSection(
                    title: "AI 입력용 영단어 JSON 복사하기",
                    systemImage: "doc.on.doc"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("저장 전 목록에 단어가 있으면 화면 아래의 ‘AI용 JSON 복사’를 눌러 외부 AI에 보낼 입력 JSON을 만들 수 있습니다.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        troubleshootingItem("저장 전 목록의 영단어만 유지되고, 뜻·예문·메모·태그는 외부 AI가 채울 수 있도록 빈 문자열로 복사됩니다.")
                        troubleshootingItem("복사한 JSON은 프롬프트 마지막의 ‘변환할 입력 JSON’ 자리에 붙여넣으세요.")
                        troubleshootingItem("이 버튼은 설정에서 ‘외부 AI의 JSON 단어 가져오기’를 켰을 때만 표시됩니다.")
                    }
                }

                helpSection(
                    title: "JSON 모드의 외부 AI 사용 시 알아두기",
                    systemImage: "hand.raised"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("JSON 모드는 외부 AI와 자동으로 연결되지 않습니다.", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text("기본 직접 입력의 Apple Intelligence 생성과 달리, 고급 JSON 모드에서는 VocaDay가 외부 AI를 열거나 단어를 보내거나 답변을 받아오지 않습니다. 사용자가 외부 AI에서 직접 만든 결과만 붙여넣습니다.")
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
            Label("기본 AI 생성은 기기 안에서 처리됩니다", systemImage: "apple.intelligence")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text("직접 입력의 뜻·품사·예문 생성은 Apple Foundation Models를 사용하며 외부 AI 서비스로 단어를 보내지 않습니다. 고급 JSON 가져오기만 사용자가 선택한 외부 AI를 별도로 이용합니다.")
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
