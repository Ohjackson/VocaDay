import SwiftUI

// MARK: - 공통: 정답/오답 배너 + 정답 + 예문 + 발음 + 계속 (SPEC §4 공통 UI)

struct ExamFeedback: Equatable {
    var isCorrect: Bool
    var title: String
    var answer: String
    var note: String? = nil
}

struct ExamFeedbackPanel: View {
    let feedback: ExamFeedback
    let word: QuizWord?
    let showsTranslation: Bool
    @ObservedObject var speech: DaySpeechPlayer
    /// 오답을 스스로 맞은 것으로 바꾸는 동작 (입력형에서만).
    var onMarkCorrect: (() -> Void)? = nil
    /// Mac에서 아무 키나 누르면 다음으로 넘어간다. 입력형 문제에서는 켜지 않는다(치던 키가 넘겨 버리지 않게).
    var advancesOnAnyKey = false
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool

    private var tint: Color { feedback.isCorrect ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(feedback.title, systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .examFont(.headline)
                    .foregroundStyle(tint)
                Spacer()
                if let word {
                    SpeakButton(text: word.example.isEmpty ? word.term : word.example, isSentence: !word.example.isEmpty, speech: speech)
                }
            }
            if !feedback.answer.isEmpty {
                Text(feedback.answer)
                    .examFont(.title3, weight: .semibold)
            }
            if let note = feedback.note {
                Text(note)
                    .examFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let word, !word.example.isEmpty {
                Button {
                    speech.speakEnglishSentence(word.example)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(word.example)
                            .examFont(.subheadline)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: speech.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .examFont(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("예문을 다시 들어요")
                if showsTranslation, !word.exampleKo.isEmpty {
                    Text(word.exampleKo)
                        .examFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if let onMarkCorrect, !feedback.isCorrect {
                    Button(action: onMarkCorrect) {
                        Text("맞은 것으로 하기").examFont(.subheadline, weight: .semibold).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .help("철자만 틀렸거나 같은 뜻의 답을 썼다면 정답으로 기록해요")
                }
                Button(action: onContinue) {
                    Text("다음").examFont(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .modifier(AnyKeyAdvance(isEnabled: advancesOnAnyKey, isFocused: $isFocused, action: onContinue))
    }
}

/// 켜져 있으면 패널이 키보드 포커스를 받아 아무 키 입력에 `action`을 실행한다.
private struct AnyKeyAdvance: ViewModifier {
    let isEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    let action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .focusable()
                .focused(isFocused)
                .focusEffectDisabled()
                .onKeyPress(phases: .down) { _ in
                    action()
                    return .handled
                }
                .onAppear { isFocused.wrappedValue = true }
        } else {
            content
        }
    }
}

struct SpeakButton: View {
    let text: String
    var isSentence = false
    @ObservedObject var speech: DaySpeechPlayer

    var body: some View {
        Button {
            if isSentence {
                speech.speakEnglishSentence(text)
            } else {
                speech.speakEnglishWord(text)
            }
        } label: {
            Image(systemName: speech.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("발음 듣기")
    }
}

private struct QuestionScaffold<Body: View, Footer: View>: View {
    let prompt: String
    @ViewBuilder let content: () -> Body
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(prompt)
                        .examFont(.headline)
                        .foregroundStyle(.secondary)
                    content()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }
}

private func posLabel(_ pos: String) -> String? {
    switch pos {
    case "noun": "명사"
    case "verb": "동사"
    case "adjective": "형용사"
    case "adverb": "부사"
    case "phrasal_verb": "구동사"
    case "idiom": "관용구"
    case "preposition": "전치사"
    case "conjunction": "접속사"
    case "other": "기타"
    default: nil
    }
}

private struct POSBadge: View {
    let pos: String

    var body: some View {
        if let label = posLabel(pos) {
            Text(label)
                .examFont(.caption, weight: .semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - 새 단어 카드 (채점 X)

struct NewWordCardView: View {
    let word: QuizWord
    let showsTranslation: Bool
    @ObservedObject var speech: DaySpeechPlayer
    let onDone: () -> Void

    var body: some View {
        QuestionScaffold(prompt: "새 단어") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Text(word.term)
                        .examFont(.largeTitle, weight: .bold)
                    SpeakButton(text: word.term, speech: speech)
                }
                HStack(spacing: 8) {
                    POSBadge(pos: word.pos)
                    Text(word.meaningKo)
                        .examFont(.title3)
                }
                if !word.disambiguationKo.isEmpty {
                    Text(word.disambiguationKo)
                        .examFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !word.example.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(word.example)
                            Spacer()
                            SpeakButton(text: word.example, speech: speech)
                        }
                        if showsTranslation, !word.exampleKo.isEmpty {
                            Text(word.exampleKo)
                                .examFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .calmCard()
                }
            }
        } footer: {
            Button(action: onDone) {
                Text("알겠어요").examFont(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .onAppear { speech.speakEnglishWord(word.term) }
    }
}

// MARK: - M1 짝 맞추기

struct MatchQuestionView: View {
    let graded: [QuizWord]
    let fillers: [QuizWord]
    let seed: String
    @ObservedObject var speech: DaySpeechPlayer
    let onComplete: ([UUID: Bool]) -> Void

    @State private var selectedEnglish: UUID?
    @State private var selectedMeaning: UUID?
    @State private var matched: Set<UUID> = []
    /// 영어 단어별 첫 연결 시도 결과 (SPEC §4 M1 채점 기준).
    @State private var firstAttempt: [UUID: Bool] = [:]
    @State private var shaking: UUID?
    @State private var isFinished = false

    private var all: [QuizWord] { graded + fillers }

    private var englishOrder: [QuizWord] {
        var generator = SeededGenerator(seed, "english")
        return all.shuffled(using: &generator)
    }

    private var meaningOrder: [QuizWord] {
        var generator = SeededGenerator(seed, "meaning")
        return all.shuffled(using: &generator)
    }

    var body: some View {
        QuestionScaffold(prompt: "짝을 맞춰 보세요") {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(englishOrder) { word in
                        tile(text: word.term, id: word.id, isSelected: selectedEnglish == word.id) {
                            speech.speakEnglishWord(word.term)
                            selectedEnglish = word.id
                            evaluate()
                        }
                    }
                }
                VStack(spacing: 10) {
                    ForEach(meaningOrder) { word in
                        tile(text: word.meaningKo, id: word.id, isSelected: selectedMeaning == word.id) {
                            selectedMeaning = word.id
                            evaluate()
                        }
                    }
                }
            }
        } footer: {
            if isFinished {
                let correct = graded.filter { firstAttempt[$0.id] == true }.count
                ExamFeedbackPanel(
                    feedback: ExamFeedback(
                        isCorrect: correct == graded.count,
                        title: correct == graded.count ? "모두 한 번에 맞혔어요!" : "\(graded.count)개 중 \(correct)개를 한 번에 맞혔어요",
                        answer: ""
                    ),
                    word: nil,
                    showsTranslation: false,
                    speech: speech
                ) {
                    onComplete(Dictionary(uniqueKeysWithValues: graded.map { ($0.id, firstAttempt[$0.id] ?? false) }))
                }
            }
        }
    }

    private func tile(text: String, id: UUID, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let isMatched = matched.contains(id)
        return Button(action: action) {
            Text(text)
                .examFont(.body, weight: .medium)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous)
                        .fill(isMatched ? Color.green.opacity(0.12) : (isSelected ? Color.accentColor.opacity(0.18) : AppTheme.cardBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : AppTheme.softStroke, lineWidth: isSelected ? 2 : 1)
                )
                .opacity(isMatched ? 0.45 : 1)
                .offset(x: shaking == id ? 6 : 0)
        }
        .buttonStyle(.plain)
        .disabled(isMatched || isFinished)
    }

    private func evaluate() {
        guard let english = selectedEnglish, let meaning = selectedMeaning else { return }
        let isCorrect = english == meaning
        if firstAttempt[english] == nil {
            firstAttempt[english] = isCorrect
        }
        if isCorrect {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = matched.insert(english)
            }
            if matched.count == all.count {
                withAnimation { isFinished = true }
            }
        } else {
            withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) {
                shaking = english
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                shaking = nil
            }
        }
        selectedEnglish = nil
        selectedMeaning = nil
    }
}

// MARK: - M2 빈칸 고르기 / M6 빈칸 고르기(번역 없이) / M5 뜻 고르기 (5지선다)

/// 보기를 누르면 바로 채점하고, 정답을 잠깐 보여 준 뒤 다음 문제로 넘어간다 (확인 버튼 없음).
struct ChoiceQuestionView: View {
    enum Style: Equatable {
        /// M2: 예문 빈칸에 들어갈 영어 표기를 고른다. 해석은 가려 두고 눌러서 볼 수 있다.
        case cloze
        /// M5: 영어 단어를 보고 한국어 뜻을 고른다.
        case meaning
    }

    let word: QuizWord
    let options: [String]
    var style: Style = .cloze
    let showsTranslation: Bool
    @ObservedObject var speech: DaySpeechPlayer
    /// 사용자가 문제 중에 예문 해석을 열었을 때.
    var onRevealTranslation: () -> Void = {}
    /// 오답 보기의 원래 단어. 결과에서 그 보기의 뜻(뜻 고르기는 영단어)을 옆에 보여 준다.
    var optionWord: (String) -> QuizWord? = { _ in nil }
    let onComplete: ([UUID: Bool]) -> Void

    @State private var selected: String?
    @State private var isCorrect: Bool?

    private var isCloze: Bool { style != .meaning }
    private var answer: String { isCloze ? word.clozeAnswer : word.meaningKo }

    var body: some View {
        QuestionScaffold(prompt: prompt) {
            promptContent
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .examFont(.caption, weight: .bold)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Color.secondary.opacity(0.1), in: Circle())
                            Text(option)
                                .examFont(.body, weight: .medium)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let gloss = revealedGloss(for: option) {
                                Text(gloss)
                                    .examFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            if isCorrect != nil, isAnswer(option) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if isCorrect == false, option == selected {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(background(for: option), in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius)
                                .stroke(stroke(for: option), lineWidth: isCorrect != nil && (isAnswer(option) || option == selected) ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    .disabled(isCorrect != nil)
                    .accessibilityLabel("\(index + 1)번, \(option)")
                }
            }
        } footer: {
            if let isCorrect {
                ExamFeedbackPanel(
                    feedback: feedback(isCorrect: isCorrect),
                    word: word,
                    // 결과에서는 문장 뜻을 항상 보여 준다.
                    showsTranslation: true,
                    speech: speech,
                    advancesOnAnyKey: Self.advancesOnAnyKey
                ) {
                    onComplete([word.id: isCorrect])
                }
            }
        }
        .onAppear {
            if style == .meaning { speech.speakEnglishWord(word.term) }
        }
    }

    private var prompt: String {
        switch style {
        case .cloze: "빈칸에 알맞은 말을 고르세요"
        case .meaning: "알맞은 뜻을 고르세요"
        }
    }

    @ViewBuilder
    private var promptContent: some View {
        switch style {
        case .cloze:
            VStack(alignment: .leading, spacing: 8) {
                Text(word.clozeSentence.replacingOccurrences(of: "<>", with: "_____"))
                    .examFont(.title3, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
                ExampleTranslationToggle(
                    translation: word.exampleKo,
                    showsByDefault: showsTranslation,
                    isLocked: isCorrect != nil,
                    onReveal: onRevealTranslation
                )
            }
        case .meaning:
            HStack(alignment: .center, spacing: 10) {
                Text(word.term)
                    .examFont(.largeTitle, weight: .bold)
                SpeakButton(text: word.term, speech: speech)
                POSBadge(pos: word.pos)
            }
        }
    }

    #if os(macOS)
    private static let advancesOnAnyKey = true
    #else
    private static let advancesOnAnyKey = false
    #endif

    private func feedback(isCorrect: Bool) -> ExamFeedback {
        ExamFeedback(
            isCorrect: isCorrect,
            title: isCorrect ? "정답이에요!" : "오답이에요",
            answer: isCloze ? answer : "\(word.term) = \(answer)",
            note: isCorrect ? nil : selected.map { "내 답: \($0)" }
        )
    }

    /// 답을 고른 뒤 정답 보기와 내가 고른 보기 옆에 붙이는 풀이: 빈칸 보기는 한국어 뜻, 뜻 보기는 영단어.
    private func revealedGloss(for option: String) -> String? {
        guard isCorrect != nil, isAnswer(option) || option == selected else { return nil }
        let source = isAnswer(option) ? word : optionWord(option)
        guard let source else { return nil }
        let gloss = isCloze ? source.meaningKo : source.term
        return gloss.isEmpty ? nil : gloss
    }

    private func isAnswer(_ option: String) -> Bool {
        isCloze ? option.lowercased() == answer.lowercased() : option == answer
    }

    private func background(for option: String) -> Color {
        guard isCorrect != nil else { return AppTheme.cardBackground }
        if isAnswer(option) { return Color.green.opacity(0.18) }
        if option == selected { return Color.red.opacity(0.15) }
        return AppTheme.cardBackground
    }

    private func stroke(for option: String) -> Color {
        guard isCorrect != nil else { return AppTheme.softStroke }
        if isAnswer(option) { return .green }
        if option == selected { return .red }
        return AppTheme.softStroke
    }

    private func choose(_ option: String) {
        guard isCorrect == nil else { return }
        let correct = isAnswer(option)
        selected = option
        withAnimation(.easeOut(duration: 0.15)) { isCorrect = correct }
        // 결과와 함께 예문을 한 번 들려준다. 예문을 누르면 다시 들을 수 있다.
        if word.example.isEmpty {
            speech.speakEnglishWord(word.term)
        } else {
            speech.speakEnglishSentence(word.example)
        }
    }
}

// MARK: - M3 빈칸 쓰기 / M4 한→영 쓰기 / M8 듣고 쓰기

struct TypingQuestionView: View {
    enum Mode: Equatable {
        case cloze(ClozeHint)
        /// 뜻을 보고 기본형 쓰기. 낮은 단계는 첫 글자·글자 수 힌트.
        case koToEn(ClozeHint)
        /// 발음만 듣고 철자 쓰기.
        case dictation

        var isCloze: Bool { if case .cloze = self { true } else { false } }
    }

    let word: QuizWord
    let mode: Mode
    let options: GradingOptions
    let showsTranslation: Bool
    @ObservedObject var speech: DaySpeechPlayer
    /// 사용자가 문제 중에 예문 해석을 열었을 때 (빈칸 쓰기).
    var onRevealTranslation: () -> Void = {}
    let onComplete: ([UUID: Bool], [UUID: String]) -> Void

    @State private var input = ""
    @State private var isRetry = false
    @State private var detail: String?
    @State private var nearMissMessage: String?
    @State private var feedback: ExamFeedback?
    @FocusState private var isFocused: Bool

    var body: some View {
        QuestionScaffold(prompt: promptTitle) {
            switch mode {
            case .cloze(let hint):
                clozePrompt(hint: hint)
            case .koToEn(let hint):
                koToEnPrompt(hint: hint)
            case .dictation:
                dictationPrompt
            }

            TextField(mode.isCloze ? "빈칸에 들어갈 말" : "영어 단어", text: $input)
                .textFieldStyle(.roundedBorder)
                .examFont(.title3)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .focused($isFocused)
                .disabled(feedback != nil)
                .onSubmit(check)

            if let nearMissMessage, feedback == nil {
                Label(nearMissMessage, systemImage: "lightbulb")
                    .examFont(.subheadline)
                    .foregroundStyle(.orange)
            }
        } footer: {
            if let feedback {
                ExamFeedbackPanel(
                    feedback: feedback,
                    word: word,
                    showsTranslation: true,
                    speech: speech,
                    onMarkCorrect: { onComplete([word.id: true], [word.id: "override"]) }
                ) {
                    onComplete([word.id: feedback.isCorrect], detail.map { [word.id: $0] } ?? [:])
                }
            } else {
                Button("확인", action: check)
                    .examFont(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { isFocused = true }
    }

    private func clozePrompt(hint: ClozeHint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(word.clozeSentence.replacingOccurrences(of: "<>", with: "_____"))
                .examFont(.title3, weight: .medium)
                .fixedSize(horizontal: false, vertical: true)
            ExampleTranslationToggle(
                translation: word.exampleKo,
                showsByDefault: showsTranslation,
                isLocked: feedback != nil,
                onReveal: onRevealTranslation
            )
            let hintText = AnswerGrader.hint(for: word.clozeAnswer, style: hint)
            if !hintText.isEmpty {
                Text(hintText)
                    .font(.body.monospaced())
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
            }
        }
    }

    private var promptTitle: String {
        switch mode {
        case .cloze: "빈칸에 들어갈 말을 써 보세요"
        case .koToEn: "영어로 써 보세요"
        case .dictation: "듣고 철자를 써 보세요"
        }
    }

    private var dictationPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                speech.speakEnglishWord(word.term)
            } label: {
                Label("다시 듣기", systemImage: speech.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .examFont(.title3, weight: .semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: .command)
            .help("다시 듣기 (⌘R)")
            Text("정답을 맞히면 뜻도 함께 보여 줘요.")
                .examFont(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { speech.speakEnglishWord(word.term) }
    }

    private func koToEnPrompt(hint: ClozeHint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                POSBadge(pos: word.pos)
            }
            Text(word.meaningKo)
                .examFont(.largeTitle, weight: .bold)
                .fixedSize(horizontal: false, vertical: true)
            if !word.disambiguationKo.isEmpty {
                Text(word.disambiguationKo)
                    .examFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if showsTranslation, !word.exampleKo.isEmpty {
                Text(word.exampleKo)
                    .examFont(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            let hintText = AnswerGrader.hint(for: word.term, style: hint)
            if !hintText.isEmpty {
                Text(hintText)
                    .examFont(.body)
                    .monospaced()
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
            }
        }
    }

    private func check() {
        guard feedback == nil, !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let outcome: GradeOutcome
        switch mode {
        case .cloze:
            outcome = AnswerGrader.gradeCloze(input, word: word, isRetry: isRetry, options: options)
        case .koToEn, .dictation:
            outcome = AnswerGrader.gradeKoToEn(input, word: word, isRetry: isRetry, options: options)
        }

        // 받아쓰기는 뜻을 모른 채 풀었으므로 결과에 뜻을 붙여 준다.
        let answer = mode.isCloze ? word.clozeAnswer : (mode == .dictation ? "\(word.term) = \(word.meaningKo)" : word.term)
        withAnimation {
            switch outcome {
            case .correct:
                feedback = ExamFeedback(isCorrect: true, title: "정답이에요!", answer: answer)
            case .typo(let expected):
                detail = "typo"
                feedback = ExamFeedback(isCorrect: true, title: "정답이에요", answer: answer, note: "오타 주의: \(expected)")
            case .nearMiss(let message):
                // 벌점 없이 한 번만 다시 입력 (SPEC §4.6).
                nearMissMessage = message
                detail = "nearMiss"
                isRetry = true
                input = ""
                isFocused = true
            case .wrong(let expected):
                feedback = ExamFeedback(isCorrect: false, title: "오답이에요", answer: mode == .dictation ? answer : expected, note: "내 답: \(input)")
            }
        }
        if case .correct = outcome, case .koToEn = mode {
            speech.speakEnglishWord(word.term)
        }
    }
}

// MARK: - M7 글자 조각 맞추기

/// 뜻을 보고 섞인 알파벳 조각을 눌러 단어를 완성한다. 떠올리기 연습이지만 키보드 철자 부담이 적다.
/// Mac·하드웨어 키보드에서는 글자를 치면 해당 조각이 놓이고, ⌫로 마지막 글자를 뺀다.
struct LetterTilesQuestionView: View {
    let word: QuizWord
    /// 섞인 조각 (정답 글자 + 가짜 글자).
    let tiles: [String]
    @ObservedObject var speech: DaySpeechPlayer
    let onComplete: ([UUID: Bool]) -> Void

    /// 놓은 조각의 인덱스 (순서대로).
    @State private var placed: [Int] = []
    @State private var feedback: ExamFeedback?
    @FocusState private var isFocused: Bool

    private var answerLetters: [String] {
        word.term.lowercased().filter { $0 != " " }.map(String.init)
    }

    private var assembled: String {
        placed.map { tiles[$0] }.joined()
    }

    var body: some View {
        QuestionScaffold(prompt: "뜻을 보고 글자를 맞춰 보세요") {
            VStack(alignment: .leading, spacing: 8) {
                POSBadge(pos: word.pos)
                Text(word.meaningKo)
                    .examFont(.largeTitle, weight: .bold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            slots

            tileGrid

            if feedback == nil {
                HStack {
                    Spacer()
                    Button {
                        removeLast()
                    } label: {
                        Label("지우기", systemImage: "delete.left")
                            .examFont(.subheadline, weight: .medium)
                    }
                    .buttonStyle(.borderless)
                    .disabled(placed.isEmpty)
                }
            }
        } footer: {
            if let feedback {
                ExamFeedbackPanel(feedback: feedback, word: word, showsTranslation: true, speech: speech) {
                    onComplete([word.id: feedback.isCorrect])
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(characters: .letters) { press in
            place(letter: press.characters.lowercased()) ? .handled : .ignored
        }
        .onKeyPress(.delete) {
            removeLast()
            return .handled
        }
        .onAppear { isFocused = true }
    }

    /// 정답 글자 수만큼 칸. 띄어쓰기는 칸 사이 간격으로 보여 준다.
    /// 단어별 칸 위치 (구동사 "give up" → [[0,1,2,3],[4,5]]).
    private var slotGroups: [[Int]] {
        var groups: [[Int]] = []
        var offset = 0
        for part in word.term.lowercased().components(separatedBy: " ") where !part.isEmpty {
            groups.append(Array(offset..<(offset + part.count)))
            offset += part.count
        }
        return groups
    }

    private var slots: some View {
        let groups = slotGroups
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { ForEach(groups.indices, id: \.self) { slotGroup(groups[$0]) } }
            VStack(alignment: .leading, spacing: 8) { ForEach(groups.indices, id: \.self) { slotGroup(groups[$0]) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("입력한 글자: \(assembled.isEmpty ? "없음" : assembled)")
    }

    private func slotGroup(_ positions: [Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(positions, id: \.self) { position in
                let letter = position < placed.count ? tiles[placed[position]] : ""
                Text(letter)
                    .examFont(.title2, weight: .semibold)
                    .frame(minWidth: 30, minHeight: 40)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(slotColor(position))
                            .frame(height: 2)
                    }
            }
        }
    }

    private func slotColor(_ position: Int) -> Color {
        guard let feedback else { return position == placed.count ? Color.accentColor : AppTheme.softStroke }
        return feedback.isCorrect ? .green : .red
    }

    private var tileGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 64), spacing: 8)], spacing: 8) {
            ForEach(tiles.indices, id: \.self) { index in
                let isUsed = placed.contains(index)
                Button {
                    placeTile(index)
                } label: {
                    Text(tiles[index])
                        .examFont(.title3, weight: .semibold)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius).stroke(AppTheme.softStroke))
                        .opacity(isUsed ? 0.25 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isUsed || feedback != nil)
                .accessibilityLabel("글자 \(tiles[index])")
            }
        }
    }

    private func placeTile(_ index: Int) {
        guard feedback == nil, !placed.contains(index), placed.count < answerLetters.count else { return }
        placed.append(index)
        if placed.count == answerLetters.count { check() }
    }

    @discardableResult
    private func place(letter: String) -> Bool {
        guard let index = tiles.indices.first(where: { tiles[$0] == letter && !placed.contains($0) }) else { return false }
        placeTile(index)
        return true
    }

    private func removeLast() {
        guard feedback == nil, !placed.isEmpty else { return }
        placed.removeLast()
    }

    private func check() {
        let isCorrect = assembled == answerLetters.joined()
        speech.speakEnglishWord(word.term)
        withAnimation {
            feedback = ExamFeedback(
                isCorrect: isCorrect,
                title: isCorrect ? "정답이에요!" : "오답이에요",
                answer: word.term,
                note: isCorrect ? nil : "내 답: \(assembled)"
            )
        }
    }
}
