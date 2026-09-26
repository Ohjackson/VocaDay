import SwiftData
import SwiftUI

/// 단어를 한 장씩 넘기며 복습합니다. 결과는 시험과 같은 SRS 장부에 기록됩니다 (`SRSStudyService`).
///
/// - iPhone/iPad: 카드를 오른쪽으로 밀면 ‘알아요’, 왼쪽으로 밀면 ‘다시’.
/// - Mac(및 하드웨어 키보드): → 알아요, ← 다시, Space 뜻 보기, ⌫ 이전 카드.
struct ReviewSessionView: View {
    let day: VocabularyDay
    let dueOnly: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var deck = ReviewDeck()
    @State private var isMeaningRevealed = false
    @State private var revealsMeaningAutomatically = false
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingDecision = false
    /// 화면을 연 시점의 오늘 남은 대상. 복습 중 목록이 바뀌지 않도록 고정한다.
    @State private var todayRemainingIDs: Set<UUID> = []
    @State private var errorAlert: VocaAlert?
    @State private var completionAlert: VocaAlert?
    @FocusState private var isDeckFocused: Bool

    private static let swipeThreshold: CGFloat = 110

    private var service: SRSStudyService { SRSStudyService(context: modelContext) }

    private var eligibleWords: [VocaWord] {
        if dueOnly {
            return day.wordList.filter { todayRemainingIDs.contains($0.id) }
        }
        return day.wordList
    }

    private var wordsByID: [UUID: VocaWord] {
        Dictionary(eligibleWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var currentWord: VocaWord? {
        deck.currentWordID.flatMap { wordsByID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            Group {
                if deck.isEmpty {
                    ContentUnavailableView("복습할 단어가 없습니다", systemImage: "checkmark.seal")
                } else if deck.isComplete {
                    completionCard
                } else if let currentWord {
                    cardStage(for: currentWord)
                }
            }
            .frame(maxWidth: 620, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)

            if !deck.isComplete, currentWord != nil {
                decisionBar
            }
        }
        .background(AppTheme.background)
        .navigationTitle(dueOnly ? "\(day.title) · 오늘 복습" : day.title)
        .toolbar { toolbarContent }
        .focusable()
        .focusEffectDisabled()
        .focused($isDeckFocused)
        .onKeyPress(.rightArrow) { handleKey { decide(.known) } }
        .onKeyPress(.leftArrow) { handleKey { decide(.again) } }
        .onKeyPress(.space) { handleKey { toggleMeaning() } }
        .onKeyPress(.delete) { handleKey { goBack() } }
        .onKeyPress(.return) {
            guard deck.isComplete else { return .ignored }
            finishReview()
            return .handled
        }
        .onAppear {
            todayRemainingIDs = Set(service.snapshot().remainingIDs)
            deck = ReviewDeck(wordIDs: eligibleWords.map(\.id).shuffled())
            isDeckFocused = true
        }
        .onChange(of: day.wordList.map(\.id)) { _, _ in
            deck.sync(with: eligibleWords.map(\.id))
        }
        .onChange(of: deck.currentWordID) { _, _ in
            isMeaningRevealed = revealsMeaningAutomatically
        }
        .onDisappear {
            speechPlayer.stop()
        }
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .background {
            // 두 번째 alert는 다른 뷰에 붙여야 첫 번째와 충돌하지 않는다.
            Color.clear.alert(item: $completionAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("확인")) { dismiss() })
            }
        }
    }

    // MARK: - 진행

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(min(deck.decidedCount + 1, max(deck.wordIDs.count, 1))) / \(deck.wordIDs.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Spacer()
                Label("\(deck.count(of: .again))", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.orange)
                Label("\(deck.count(of: .known))", systemImage: "checkmark")
                    .foregroundStyle(.green)
            }
            .font(.subheadline.monospacedDigit())

            ProgressView(value: Double(deck.decidedCount), total: Double(max(deck.wordIDs.count, 1)))
                .tint(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: 660)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.wordIDs.count)개 중 \(deck.decidedCount)개 판단, 다시 \(deck.count(of: .again))개, 알아요 \(deck.count(of: .known))개")
    }

    // MARK: - 카드

    private func cardStage(for word: VocaWord) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            wordCard(for: word)
                .id(word.id)
                .offset(x: dragOffset)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragOffset / 28)))
                .overlay(alignment: .topLeading) { swipeStamp(.known) }
                .overlay(alignment: .topTrailing) { swipeStamp(.again) }
                .gesture(swipeGesture)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))

            Text(interactionHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
    }

    private func wordCard(for word: VocaWord) -> some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button {
                    speechPlayer.speakEnglishWord(word.english)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(word.english) 발음 듣기")
            }

            Text(word.english)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            if isMeaningRevealed {
                meaningContent(for: word)
                    .transition(.opacity)
            } else {
                Button(action: toggleMeaning) {
                    Label("뜻 보기", systemImage: "eye")
                        .frame(maxWidth: 240, minHeight: 36)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 460)
        .calmCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleMeaning)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "다시") { decide(.again) }
        .accessibilityAction(named: "알아요") { decide(.known) }
    }

    private func meaningContent(for word: VocaWord) -> some View {
        VStack(spacing: 12) {
            Text(trimmed(word.meaningKo) ?? "뜻 없음")
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)

            let examples = ExamText.examplePairs(en: word.exampleEn, ko: word.exampleKo).filter { !$0.en.isEmpty }
            if !examples.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                        VStack(spacing: 4) {
                            Text(example.en)
                                .font(.callout)
                            if !example.ko.isEmpty {
                                Text(example.ko)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 10))
            }

            let tags = [word.note, word.toeicTag].compactMap(trimmed)
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func swipeStamp(_ decision: ReviewDecision) -> some View {
        let progress = decision == .known ? dragOffset : -dragOffset
        let opacity = min(max(progress / Self.swipeThreshold, 0), 1)
        let color: Color = decision == .known ? .green : .orange

        Text(decision == .known ? "알아요" : "다시")
            .font(.headline.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 2))
            .rotationEffect(.degrees(decision == .known ? -12 : 12))
            .padding(18)
            .opacity(opacity)
            .offset(x: dragOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isAnimatingDecision else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !isAnimatingDecision else { return }
                let predicted = value.predictedEndTranslation.width
                if value.translation.width > Self.swipeThreshold || predicted > Self.swipeThreshold * 2 {
                    decide(.known)
                } else if value.translation.width < -Self.swipeThreshold || predicted < -Self.swipeThreshold * 2 {
                    decide(.again)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// 키보드가 기본인 Mac에서만 버튼에 방향키 힌트를 붙인다.
    private static func keyHint(_ key: String) -> String {
        #if os(macOS)
        " · \(key)"
        #else
        ""
        #endif
    }

    private var interactionHint: String {
        #if os(macOS)
        "← 다시 · Space 뜻 보기 · → 알아요 · ⌫ 이전 카드"
        #else
        "왼쪽으로 밀면 다시 · 오른쪽으로 밀면 알아요 · 카드를 누르면 뜻 보기"
        #endif
    }

    // MARK: - 하단 버튼

    private var decisionBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                Button(action: goBack) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!deck.canGoBack)
                .accessibilityLabel("이전 카드")
                .help("이전 카드 (⌫)")

                decisionButton(.again)
                decisionButton(.known)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .background(.regularMaterial)
    }

    private func decisionButton(_ decision: ReviewDecision) -> some View {
        let isKnown = decision == .known
        let color: Color = isKnown ? .green : .orange

        return Button {
            decide(decision)
        } label: {
            VStack(spacing: 2) {
                Label(isKnown ? "알아요" : "다시", systemImage: isKnown ? "checkmark" : "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                Text(isKnown ? "복습 간격 늘리기\(Self.keyHint("→"))" : "곧 다시 보기\(Self.keyHint("←"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(isKnown ? "알아요 (→)" : "다시 (←)")
    }

    // MARK: - 완료

    private var completionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)

            Text("모든 카드를 확인했어요")
                .font(.title3.weight(.semibold))

            HStack(spacing: 24) {
                resultStat(title: "알아요", value: deck.count(of: .known), color: .green)
                resultStat(title: "다시", value: deck.count(of: .again), color: .orange)
            }

            Button(action: finishReview) {
                Label("복습 완료", systemImage: "checkmark.circle")
                    .frame(minWidth: 180, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button("마지막 카드로 돌아가기", action: goBack)
                .buttonStyle(.borderless)
                .font(.subheadline)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .calmCard()
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func resultStat(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                autoRevealToggle
                shuffleButton
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("복습 보기 설정")
            .disabled(deck.isEmpty)
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            autoRevealToggle
            shuffleButton
        }
        #endif
    }

    private var autoRevealToggle: some View {
        Toggle(isOn: $revealsMeaningAutomatically) {
            Label("뜻 바로 보기", systemImage: "eye")
        }
        .onChange(of: revealsMeaningAutomatically) { _, reveals in
            isMeaningRevealed = reveals
        }
    }

    private var shuffleButton: some View {
        Button {
            withAnimation { deck.shuffleRemaining() }
        } label: {
            Label("남은 카드 섞기", systemImage: "shuffle")
        }
        .disabled(deck.isComplete)
    }

    // MARK: - 동작

    private func handleKey(_ action: () -> Void) -> KeyPress.Result {
        guard !deck.isComplete, currentWord != nil else { return .ignored }
        action()
        return .handled
    }

    private func toggleMeaning() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isMeaningRevealed.toggle()
        }
    }

    private func decide(_ decision: ReviewDecision) {
        guard !isAnimatingDecision, currentWord != nil else { return }

        guard !reduceMotion else {
            deck.decide(decision)
            dragOffset = 0
            return
        }

        isAnimatingDecision = true
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = decision == .known ? 700 : -700
        } completion: {
            dragOffset = 0
            withAnimation(.easeOut(duration: 0.18)) {
                deck.decide(decision)
            }
            isAnimatingDecision = false
            isDeckFocused = true
        }
    }

    private func goBack() {
        guard deck.canGoBack, !isAnimatingDecision else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            deck.goBack()
        }
        isDeckFocused = true
    }

    /// 판단을 SRS에 넘긴다. 오늘 대상은 장부로(모두 채워지면 반영), 대상이 아닌 단어는 미리 복습 규칙으로.
    private func finishReview() {
        guard deck.isComplete else { return }

        let decisions = deck.wordIDs.compactMap { id -> (wordID: UUID, known: Bool)? in
            guard wordsByID[id] != nil, let decision = deck.decisions[id] else { return nil }
            return (id, decision == .known)
        }
        let service = service
        let recorded = service.recordFlashcards(decisions)

        day.reviewSessionCount += 1
        day.reviewedWordCount += decisions.count
        day.lastReviewedAt = Date()
        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }

        do {
            if let finalization = try service.finalizeIfComplete() {
                completionAlert = Self.completionMessage(for: finalization)
                return
            }
        } catch {
            errorAlert = VocaAlert(title: "저장 실패", message: error.localizedDescription)
            return
        }

        let remaining = service.snapshot().remainingCount
        if recorded.graded > 0, remaining > 0 {
            completionAlert = VocaAlert(
                title: "복습을 기록했어요",
                message: "오늘 복습할 단어가 \(remaining)개 남았어요. 다른 데이의 복습이나 시험으로 마저 풀면 오늘 학습이 반영돼요."
            )
        } else if recorded.lapsed > 0 {
            completionAlert = VocaAlert(
                title: "복습을 기록했어요",
                message: "'다시'로 고른 단어 \(recorded.lapsed)개는 오늘 복습 목록에 추가했어요."
            )
        } else {
            dismiss()
        }
    }

    private static func completionMessage(for finalization: SRSStudyService.Finalization) -> VocaAlert {
        let wrong = finalization.outcome.retryWordIDs.count
        if finalization.kind == .first, wrong > 0 {
            return VocaAlert(
                title: "오늘 복습을 마쳤어요",
                message: "틀린 단어 \(wrong)개는 \(SRSEngine.retryDelayHours)시간 뒤 재도전에서 다시 나와요. 알람으로 알려 드릴게요."
            )
        }
        return VocaAlert(
            title: "오늘 학습 완료",
            message: "맞힌 단어는 다음 복습까지 간격이 늘어났어요. 다음 복습 예정일에 다시 불러올게요."
        )
    }

    private func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
