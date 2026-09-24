import SwiftData
import SwiftUI

private enum ReviewListScope: String, CaseIterable, Identifiable {
    case due
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .due: "오늘 복습"
        case .all: "전체 데이"
        }
    }
}

struct ReviewView: View {
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @State private var scope: ReviewListScope = .due

    private var dueWordCount: Int {
        days.reduce(0) { count, day in
            count + day.wordList.filter { ReviewScheduler.isDue($0) }.count
        }
    }

    private var dueDays: [VocabularyDay] {
        days.filter { dueCount(for: $0) > 0 }
    }

    private var displayedDays: [VocabularyDay] {
        scope == .due ? dueDays : days
    }

    private var nextScheduledReviewDate: Date? {
        days
            .flatMap(\.wordList)
            .map(\.nextReviewAt)
            .filter { $0 > Date() }
            .min()
    }

    var body: some View {
        AppCollectionPage(
            maxContentWidth: 840,
            horizontalPadding: 20,
            verticalPadding: 24
        ) {
            VStack(alignment: .leading, spacing: 18) {
                reviewSummary

                Picker("복습 범위", selection: $scope) {
                    ForEach(ReviewListScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if days.isEmpty {
                    EmptyStateView(
                        title: "아직 데이가 없습니다. 단어를 먼저 추가해 보세요.",
                        systemImage: "calendar"
                    )
                    .padding(.top, 32)
                    .componentSpotlight(.reviewDay)
                } else if displayedDays.isEmpty {
                    completedState
                        .componentSpotlight(.reviewDay)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(displayedDays) { day in
                            reviewDayRow(for: day)
                                .componentSpotlight(
                                    day.id == displayedDays.first?.id ? .reviewDay : .dayCollection
                                )
                        }
                    }
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("복습")
    }

    private var reviewSummary: some View {
        HStack(spacing: 14) {
            Image(systemName: dueWordCount == 0 ? "checkmark.circle.fill" : "rectangle.stack.fill")
                .font(.title2)
                .foregroundStyle(dueWordCount == 0 ? Color.green : Color.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    (dueWordCount == 0 ? Color.green : Color.accentColor).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(dueWordCount == 0 ? "오늘 복습을 마쳤어요" : "오늘 복습할 단어 \(dueWordCount)개")
                    .font(.headline)

                if dueWordCount > 0 {
                    Text("\(dueDays.count)개 데이에 복습할 단어가 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let nextScheduledReviewDate {
                    Text("다음 복습은 \(nextScheduledReviewDate.formatted(date: .abbreviated, time: .omitted)) 예정입니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("단어를 추가하면 오늘의 복습에 표시됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .calmCard()
        .accessibilityElement(children: .combine)
    }

    private var completedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.green)
            Text("오늘 예정된 복습이 없습니다")
                .font(.headline)
            Text("원하면 전체 데이에서 단어를 자유롭게 복습할 수 있어요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("전체 데이 보기") {
                scope = .all
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func reviewDayRow(for day: VocabularyDay) -> some View {
        let dueOnly = scope == .due

        return NavigationLink {
            ReviewDayDetailView(day: day, dueOnly: dueOnly)
        } label: {
            DayCardView(
                day: day,
                isSelected: false,
                dueReviewCount: dueCount(for: day)
            )
        }
        .buttonStyle(.plain)
    }

    private func dueCount(for day: VocabularyDay) -> Int {
        day.wordList.filter { ReviewScheduler.isDue($0) }.count
    }
}

private enum ReviewDecision: String {
    case again
    case known
}

private struct ReviewDayDetailView: View {
    let day: VocabularyDay
    let dueOnly: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var decisions: [UUID: ReviewDecision] = [:]
    @State private var revealedMeaningIDs: Set<UUID> = []
    @State private var expandedWordIDs: Set<UUID> = []
    @State private var showsWordDetails = false
    @State private var randomWordIDs: [UUID] = []
    @State private var reviewStartedAt = Date()
    @State private var errorAlert: VocaAlert?

    private var eligibleWords: [VocaWord] {
        if dueOnly {
            return day.wordList.filter { ReviewScheduler.isDue($0, now: reviewStartedAt) }
        }
        return day.wordList
    }

    private var reviewWords: [VocaWord] {
        let wordsByID = Dictionary(uniqueKeysWithValues: eligibleWords.map { ($0.id, $0) })
        let orderedWords = randomWordIDs.compactMap { wordsByID[$0] }
        let missingWords = eligibleWords
            .filter { !randomWordIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        return orderedWords + missingWords
    }

    private var hasDecidedEveryWord: Bool {
        !reviewWords.isEmpty && reviewWords.allSatisfy { decisions[$0.id] != nil }
    }

    private var againCount: Int {
        decisions.values.filter { $0 == .again }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    reviewGuide

                    ForEach(Array(reviewWords.enumerated()), id: \.element.id) { index, word in
                        reviewCard(for: word, index: index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            submitBar
        }
        .background(AppTheme.background)
        .navigationTitle(dueOnly ? "\(day.title) · 오늘 복습" : day.title)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            reviewStartedAt = Date()
            syncRandomOrder()
        }
        .onChange(of: day.wordList.map(\.id)) { _, _ in
            syncRandomOrder()
        }
        .onDisappear {
            speechPlayer.stop()
        }
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var reviewGuide: some View {
        Label(
            "뜻을 확인한 뒤 모든 단어를 ‘다시’ 또는 ‘알아요’로 판단하세요.",
            systemImage: "lightbulb"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func reviewCard(for word: VocaWord, index: Int) -> some View {
        let revealsMeaning = revealedMeaningIDs.contains(word.id)
        let showsDetails = showsWordDetails || expandedWordIDs.contains(word.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.1), in: Circle())

                Text(word.english)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    speechPlayer.speakEnglishWord(word.english)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(word.english) 발음 듣기")

                Button {
                    toggleDetails(for: word)
                } label: {
                    Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showsDetails ? "세부 정보 숨기기" : "세부 정보 보기")
            }

            Group {
                if revealsMeaning {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.meaningKo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "뜻 없음" : word.meaningKo)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("가리기") {
                            revealedMeaningIDs.remove(word.id)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        revealedMeaningIDs.insert(word.id)
                    } label: {
                        Label("뜻 보기", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: 10))

            if showsDetails {
                Divider()
                detailLine("영어 예문", word.exampleEn)
                detailLine("예문 번역", word.exampleKo)
                detailLine("메모", word.note)
                detailLine("태그", word.toeicTag)
            }

            HStack(spacing: 10) {
                decisionButton(
                    title: "다시",
                    subtitle: "오늘 다시 보기",
                    systemImage: "arrow.counterclockwise",
                    decision: .again,
                    word: word,
                    color: .orange
                )

                decisionButton(
                    title: "알아요",
                    subtitle: "다음 복습 예약",
                    systemImage: "checkmark",
                    decision: .known,
                    word: word,
                    color: .green
                )
            }
        }
        .padding(16)
        .calmCard()
    }

    private func decisionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        decision: ReviewDecision,
        word: VocaWord,
        color: Color
    ) -> some View {
        let isSelected = decisions[word.id] == decision

        return Button {
            decisions[word.id] = decision
        } label: {
            VStack(spacing: 3) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? color : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isSelected ? color : Color.primary)
            .background(color.opacity(isSelected ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(decisions.count)/\(reviewWords.count)개 판단")
                        .font(.subheadline.weight(.semibold))
                    if againCount > 0 {
                        Text("다시 볼 단어 \(againCount)개")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    finishReview()
                } label: {
                    Label("복습 완료", systemImage: "checkmark.circle")
                        .frame(minWidth: 130, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasDecidedEveryWord)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private func shuffleWords() {
        randomWordIDs = eligibleWords.map(\.id).shuffled()
    }

    private func syncRandomOrder() {
        let wordIDs = eligibleWords.map(\.id)
        let currentIDs = Set(wordIDs)
        let orderedIDs = randomWordIDs.filter { currentIDs.contains($0) }
        let missingIDs = wordIDs.filter { !orderedIDs.contains($0) }.shuffled()

        randomWordIDs = orderedIDs + missingIDs
        decisions = decisions.filter { currentIDs.contains($0.key) }
        revealedMeaningIDs.formIntersection(currentIDs)
        expandedWordIDs.formIntersection(currentIDs)
    }

    private func finishReview() {
        guard hasDecidedEveryWord else { return }

        let now = Date()
        for word in reviewWords {
            switch decisions[word.id] {
            case .again:
                ReviewScheduler.markAgain(word, now: now)
            case .known:
                ReviewScheduler.markKnown(word, now: now)
            case nil:
                return
            }
        }

        day.reviewSessionCount += 1
        day.reviewedWordCount += reviewWords.count
        day.lastReviewedAt = now

        if let error = modelContext.saveReportingError() {
            errorAlert = .saveFailure(error)
            return
        }
        dismiss()
    }

    private func toggleDetails(for word: VocaWord) {
        if expandedWordIDs.contains(word.id) {
            expandedWordIDs.remove(word.id)
        } else {
            expandedWordIDs.insert(word.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                detailsToggle
                revealAllButton
                shuffleButton
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("복습 보기 설정")
            .disabled(reviewWords.isEmpty)
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            detailsToggle
            revealAllButton
            shuffleButton
        }
        #endif
    }

    private var detailsToggle: some View {
        Toggle(isOn: $showsWordDetails) {
            Label(showsWordDetails ? "모든 세부 정보 숨기기" : "모든 세부 정보 보기", systemImage: "text.justify")
        }
    }

    private var revealAllButton: some View {
        Button {
            let allIDs = Set(reviewWords.map(\.id))
            if revealedMeaningIDs == allIDs {
                revealedMeaningIDs.removeAll()
            } else {
                revealedMeaningIDs = allIDs
            }
        } label: {
            Label(
                revealedMeaningIDs.count == reviewWords.count ? "모든 뜻 가리기" : "모든 뜻 보기",
                systemImage: revealedMeaningIDs.count == reviewWords.count ? "eye.slash" : "eye"
            )
        }
    }

    private var shuffleButton: some View {
        Button(action: shuffleWords) {
            Label("순서 섞기", systemImage: "shuffle")
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
