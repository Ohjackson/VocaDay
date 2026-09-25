import SwiftData
import SwiftUI

/// "시험" 탭. 단고초 홈의 학습 버튼 3상태(SPEC §2.4)와 보강 상태를 보여 준다.
struct ExamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \VocaWord.createdAt) private var words: [VocaWord]
    @Query private var progressRecords: [StudyProgress]
    @ObservedObject private var enrichment = ExamEnrichmentCoordinator.shared

    @Environment(\.appNavigate) private var navigate
    @State private var isShowingSession = false
    @State private var isShowingSettings = false
    @State private var hasAPIKey = GeminiAPIKeyStore.standard.hasAPIKey

    private var progress: StudyProgress? {
        StudyProgressStore.preferred(progressRecords)
    }

    private var sessionState: SRSSessionState {
        progress?.sessionState ?? .initial
    }

    /// 장부가 바뀌면(복습 카드 기록) 남은 수를 다시 계산한다.
    @AppStorage(StudyDayLedgerStore.storageKey) private var ledgerData: Data?

    private func snapshot(now: Date) -> StudyQueueSnapshot {
        _ = ledgerData
        return StudyQueue.snapshot(words: words, progress: progress, now: now)
    }

    private var overdueTotal: Int {
        words.filter { $0.srsNextLearningDay <= sessionState.currentLearningDay }.count
    }

    private var resumableSession: ActiveExamSession? {
        guard let saved = ExamSessionStore.standard.load(),
              saved.learningDay == sessionState.currentLearningDay,
              saved.answeredGradedCount > 0 || saved.cursor > 0 else { return nil }
        return saved
    }

    var body: some View {
        AppCollectionPage(maxContentWidth: 720, horizontalPadding: 20, verticalPadding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    statusCard(now: context.date)
                }
                LearningMethodCard()
                enrichmentCard
                stageDistribution
            }
        }
        .background(AppTheme.background)
        .navigationTitle("시험")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("시험 설정", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: refreshKeyState) {
            NavigationStack {
                ExamSettingsView()
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isShowingSession) {
            ExamSessionView()
        }
        #endif
        .task {
            _ = StudyProgressStore.fetchOrCreate(in: modelContext)
            enrichment.runIfPossible(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                enrichment.runIfPossible(context: modelContext)
            }
        }
    }

    /// Mac은 시트 대신 본문 열에 push 합니다. 고정 높이 시트는 창보다 커지면 창 아래로 넘칩니다.
    private func openSession() {
        #if os(macOS)
        navigate(.examSession)
        #else
        isShowingSession = true
        #endif
    }

    // MARK: 학습 버튼

    private func statusCard(now: Date) -> some View {
        let snapshot = snapshot(now: now)
        let status = snapshot.status
        let canStart = snapshot.kind != nil && (snapshot.remainingCount > 0 || snapshot.isReadyToFinalize)
        let resumable = resumableSession

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(for: snapshot))
                        .font(.title3.weight(.semibold))
                    Text(subheadline(for: snapshot))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("학습일 \(sessionState.currentLearningDay + 1)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if !snapshot.targetIDs.isEmpty {
                ProgressView(value: Double(snapshot.gradedIDs.count), total: Double(snapshot.targetIDs.count)) {
                    Text("오늘 \(snapshot.gradedIDs.count)/\(snapshot.targetIDs.count)개 완료 · 복습 카드와 시험 합산")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.green)
            }

            Button {
                openSession()
            } label: {
                Text(buttonTitle(for: snapshot, resumable: resumable != nil))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            if let resumable, status.isButtonEnabled, canStart {
                Text("진행 중인 시험이 있어요 · \(resumable.answeredGradedCount)/\(resumable.plan.gradedCount) 문제 완료")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.cardPadding)
        .calmCard()
    }

    private func buttonTitle(for snapshot: StudyQueueSnapshot, resumable: Bool) -> String {
        if snapshot.isDoneForToday { return "오늘 학습 완료" }
        guard snapshot.status.isButtonEnabled else { return snapshot.status.buttonTitle }
        if snapshot.isReadyToFinalize { return "오늘 결과 반영하기" }
        if resumable { return "이어서 풀기" }
        return snapshot.gradedIDs.isEmpty ? snapshot.status.buttonTitle : "남은 \(snapshot.remainingCount)개 풀기"
    }

    private func headline(for snapshot: StudyQueueSnapshot) -> String {
        if snapshot.isDoneForToday { return "오늘 학습을 마쳤어요" }
        switch snapshot.status {
        case .readyForFirstSession:
            return snapshot.targetIDs.isEmpty ? "오늘 복습할 단어가 없어요" : "오늘 복습할 단어 \(snapshot.remainingCount)개"
        case .waitingForRetry:
            return "틀린 단어 \(sessionState.wrongAnswerWordIDs.count)개 재도전 대기 중"
        case .readyForRetry:
            return "틀린 단어 \(snapshot.remainingCount)개 재도전"
        }
    }

    private func subheadline(for snapshot: StudyQueueSnapshot) -> String {
        if snapshot.isDoneForToday {
            return snapshot.upcomingCount > 0
                ? "다음 학습(단어 \(snapshot.upcomingCount)개)은 내일 열려요. 하루 한 번씩 간격을 두어야 오래 기억해요."
                : "새 단어를 추가하면 내일 학습에 나와요."
        }
        switch snapshot.status {
        case .readyForFirstSession:
            if words.isEmpty { return "단어를 추가하면 시험을 볼 수 있어요." }
            if snapshot.targetIDs.isEmpty { return "새 단어를 추가하면 바로 시험에 나와요." }
            let extra = overdueTotal - snapshot.targetIDs.count
            return extra > 0
                ? "하루 최대 \(SRSEngine.dailyReviewLimit)개씩 나와요. 남은 \(extra)개는 다음 학습에 먼저 나와요."
                : "짝 맞추기·뜻 고르기·빈칸 고르기·빈칸 쓰기가 섞여 나와요."
        case .waitingForRetry(_, let availableAt):
            return "\(availableAt.formatted(date: .omitted, time: .shortened))부터 다시 풀 수 있어요. 재도전을 마치면 오늘 학습이 끝나요."
        case .readyForRetry:
            return "재도전을 마치면 오늘 학습이 끝나요."
        }
    }

    // MARK: 보강

    private var enrichmentCard: some View {
        let pending = enrichment.pendingWords(in: words).count
        let failed = enrichment.failedWordCount(in: words)
        let notReady = words.filter { !$0.quizWord.hasCloze }

        return VStack(alignment: .leading, spacing: 10) {
            Label("문제 준비", systemImage: "sparkles")
                .font(.headline)

            Text("\(words.count)개 중 \(words.count - notReady.count)개 단어가 네 가지 유형을 모두 풀 수 있어요.")
                .font(.subheadline)

            if !notReady.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("예문에 단어가 없어 빈칸 문제를 못 만드는 단어 \(notReady.count)개: \(notReady.prefix(6).map(\.english).joined(separator: ", "))\(notReady.count > 6 ? " 외" : "")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("데이 단어 목록에서 그 단어가 들어간 영어 예문으로 고치면 바로 준비돼요. 그 전까지는 짝 맞추기·뜻 고르기로 나와요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            if enrichment.isRunning {
                ProgressView(value: Double(enrichment.processedCount), total: Double(max(enrichment.totalCount, 1))) {
                    Text("Gemini로 예문과 활용형을 만드는 중… \(enrichment.processedCount)/\(enrichment.totalCount)")
                        .font(.caption)
                }
            } else if !hasAPIKey {
                Text("선택: 시험 설정에서 Gemini API 키를 넣으면 품사·활용형까지 분석해 보기를 더 정교하게 만들어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if pending > 0 {
                Button("\(pending)개 단어 문제 만들기") {
                    Task { await enrichment.run(context: modelContext) }
                }
                .buttonStyle(.bordered)
            }

            if failed > 0, !enrichment.isRunning {
                HStack {
                    Text("\(failed)개는 AI 응답이 검증을 통과하지 못했어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("다시 시도") {
                        enrichment.resetFailures()
                        Task { await enrichment.run(context: modelContext) }
                    }
                    .font(.caption)
                    .disabled(!hasAPIKey)
                }
            }

            if let message = enrichment.lastMessage, !enrichment.isRunning {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .calmCard()
    }

    // MARK: 단계 분포

    private var stageDistribution: some View {
        let buckets: [(String, ClosedRange<Int>)] = [("새 단어", 0...0), ("익히는 중", 1...4), ("익숙함", 5...7), ("장기 기억", 8...10)]
        return VStack(alignment: .leading, spacing: 10) {
            Text("단계별 단어")
                .font(.headline)
            HStack(spacing: 10) {
                ForEach(buckets, id: \.0) { title, range in
                    VStack(spacing: 4) {
                        Text("\(words.filter { range.contains($0.srsStage) }.count)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .calmCard()
    }

    private func refreshKeyState() {
        hasAPIKey = GeminiAPIKeyStore.standard.hasAPIKey
        enrichment.runIfPossible(context: modelContext)
    }
}
