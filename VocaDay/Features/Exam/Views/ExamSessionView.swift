import SwiftData
import SwiftUI

/// 시험 세션 화면: 진행 바 + 문제 + 레슨 사이 화면 + 결과 (SPEC §3, §4, §5).
struct ExamSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ExamSettingsKeys.showsExampleTranslation) private var showsTranslation = false

    var body: some View {
        ExamSessionContent(context: modelContext, showsTranslation: showsTranslation) {
            dismiss()
        }
    }
}

private struct ExamSessionContent: View {
    @StateObject private var viewModel: ExamSessionViewModel
    @StateObject private var speech = DaySpeechPlayer()
    let showsTranslation: Bool
    let onClose: () -> Void

    init(context: ModelContext, showsTranslation: Bool, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ExamSessionViewModel(context: context))
        self.showsTranslation = showsTranslation
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = ExamTypography.scale(forWidth: proxy.size.width)
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                content
                    .frame(maxWidth: 640 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // 넓은 화면(iPad·큰 Mac 창)에서는 글씨와 본문 폭이 함께 커진다.
            .environment(\.examTextScale, scale)
        }
        .background(AppTheme.background)
        .task {
            if viewModel.phase == .loading {
                viewModel.start()
            }
        }
        .onDisappear {
            speech.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .examFont(.body, weight: .semibold)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("나가기 (진행 상황은 저장돼요)")

            if viewModel.isReplaying {
                Label("오답 다시 풀기", systemImage: "arrow.counterclockwise")
                    .examFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.orange)
                Spacer()
            } else {
                ProgressView(value: viewModel.progress)
                    .tint(.green)
                Text("\(viewModel.gradedDone)/\(viewModel.gradedTotal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
        case .unavailable(let message):
            messageView(systemImage: "checkmark.circle", title: message, buttonTitle: "닫기", action: onClose)
        case .question:
            if let item = viewModel.currentItem {
                question(for: item)
                    .id(viewModel.itemToken)
            }
        case .saveFailed(let message):
            messageView(systemImage: "exclamationmark.triangle", title: message, buttonTitle: "다시 저장") {
                viewModel.retrySaving()
            }
        case .replayIntro(let wrongCount, let hintCount):
            replayIntro(wrongCount: wrongCount, hintCount: hintCount)
        case .finished:
            if let summary = viewModel.summary {
                ExamResultView(summary: summary, onClose: onClose)
            } else {
                messageView(systemImage: "checkmark.circle", title: "학습을 마쳤어요", buttonTitle: "닫기", action: onClose)
            }
        }
    }

    @ViewBuilder
    private func question(for item: ExamPlanItem) -> some View {
        let words = item.wordIDs.compactMap(viewModel.word)
        let complete: ([UUID: Bool]) -> Void = { viewModel.complete(results: $0) }
        switch item.kind {
        case .newWord:
            if let word = words.first {
                // 새 단어 카드는 외우는 화면이므로 해석을 항상 보여 준다.
                NewWordCardView(word: word, showsTranslation: true, speech: speech) {
                    viewModel.complete(results: [:])
                }
            }
        case .match:
            MatchQuestionView(
                graded: words,
                fillers: item.fillerWordIDs.compactMap(viewModel.word),
                seed: "\(viewModel.session?.sessionID.uuidString ?? "")|\(viewModel.itemToken)",
                speech: speech,
                onComplete: complete
            )
        case .choice, .clozeChoiceWithoutTranslation:
            if let word = words.first {
                ChoiceQuestionView(
                    word: word,
                    options: item.options,
                    style: .cloze,
                    showsTranslation: showsTranslation,
                    speech: speech,
                    onRevealTranslation: { viewModel.markTranslationViewed() },
                    optionWord: { viewModel.word(forChoiceOption: $0, isMeaning: false) },
                    onComplete: complete
                )
            }
        case .meaningChoice:
            if let word = words.first {
                ChoiceQuestionView(
                    word: word,
                    options: item.options,
                    style: .meaning,
                    showsTranslation: showsTranslation,
                    speech: speech,
                    optionWord: { viewModel.word(forChoiceOption: $0, isMeaning: true) },
                    onComplete: complete
                )
            }
        case .flashcard:
            EmptyView()
        case .clozeTyping:
            if let word = words.first {
                TypingQuestionView(
                    word: word,
                    mode: .cloze(item.hint ?? .none),
                    options: viewModel.gradingOptions,
                    showsTranslation: showsTranslation,
                    speech: speech,
                    onRevealTranslation: { viewModel.markTranslationViewed() },
                    onComplete: { viewModel.complete(results: $0, details: $1) }
                )
            }
        case .koToEn, .dictation:
            if let word = words.first {
                TypingQuestionView(
                    word: word,
                    mode: item.kind == .dictation ? .dictation : .koToEn(item.hint ?? .none),
                    options: viewModel.gradingOptions,
                    // 한→영 쓰기에서 한국어 문장은 문제 자체(맥락)이므로 항상 보여 준다.
                    showsTranslation: true,
                    speech: speech,
                    onComplete: { viewModel.complete(results: $0, details: $1) }
                )
            }
        case .letterTiles:
            if let word = words.first {
                LetterTilesQuestionView(word: word, tiles: item.options, speech: speech, onComplete: complete)
            }
        }
    }

    private func replayIntro(wrongCount: Int, hintCount: Int) -> some View {
        let title: String
        switch (wrongCount > 0, hintCount > 0) {
        case (true, true): title = "틀린 문제 \(wrongCount)개와 해석을 본 문제 \(hintCount)개를 한 번 더 풀어요"
        case (true, false): title = "틀린 단어 \(wrongCount)개를 다시 풀어 볼까요?"
        default: title = "해석을 본 문제 \(hintCount)개를 이번엔 해석 없이 풀어 봐요"
        }
        return VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text(title)
                .examFont(.title3, weight: .bold)
                .multilineTextAlignment(.center)
            Text(wrongCount > 0
                 ? "맞힐 때까지 반복하는 연습이에요. 오늘 결과는 이미 저장됐고, 재도전은 \(SRSEngine.retryDelayHours)시간 뒤에 열려요."
                 : "오늘 결과는 이미 저장됐어요. 한 번 더 풀어 보면 해석 없이도 떠올리는 연습이 돼요.")
                .examFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 10) {
                Button {
                    viewModel.startReplay()
                } label: {
                    Text("다시 풀기").examFont(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("결과 보기") {
                    viewModel.skipReplay()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    private func messageView(systemImage: String, title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .examFont(.headline)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

// MARK: - 결과 화면 (SPEC §5)

struct ExamResultView: View {
    let summary: ExamResultSummary
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 6) {
                        Text("\(summary.correctCount) / \(summary.rows.count)")
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                        Text(summary.kind == .retry ? "재도전을 마쳤어요. 다음 학습일로 넘어가요." : "오늘의 학습 결과")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    if summary.retryScheduledAt != nil {
                        Label("\(SRSEngine.retryDelayHours)시간 뒤 재도전 알림을 예약했어요", systemImage: "bell.badge")
                            .examFont(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))
                    }

                    VStack(spacing: 0) {
                        ForEach(summary.rows) { row in
                            HStack(spacing: 12) {
                                Image(systemName: row.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(row.isCorrect ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.term).examFont(.body, weight: .semibold)
                                    Text(row.meaningKo).examFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(row.stageBefore) → \(row.stageAfter)")
                                        .font(.subheadline.monospacedDigit())
                                    Text(row.learningDaysUntilNext == 0 ? "다음 학습에" : "\(row.learningDaysUntilNext)학습일 뒤")
                                        .examFont(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            Divider().opacity(0.4)
                        }
                    }
                    .calmCard()
                }
                .padding(20)
            }
            Button {
                onClose()
            } label: {
                Text("완료").examFont(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(20)
        }
    }
}
