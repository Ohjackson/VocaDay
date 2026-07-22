import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @State private var isEditingDays = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if days.isEmpty {
                    EmptyStateView(
                        title: "No Day exists yet.",
                        systemImage: "calendar"
                    )
                    .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(days) { day in
                            dayRow(for: day)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 840, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.background)
        .onboardingSpotlight(.review)
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Button {
                    isEditingDays.toggle()
                } label: {
                    Image(systemName: isEditingDays ? "checkmark" : "square.and.pencil")
                }
                .accessibilityLabel(isEditingDays ? "Done Editing Days" : "Edit Days")
                .disabled(days.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func dayRow(for day: VocabularyDay) -> some View {
        if isEditingDays {
            HStack(spacing: 10) {
                DayCardView(day: day, isSelected: false)

                Button(role: .destructive) {
                    delete(day)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(day.title)")
            }
        } else {
            NavigationLink {
                ReviewDayDetailView(day: day)
            } label: {
                DayCardView(day: day, isSelected: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func delete(_ day: VocabularyDay) {
        modelContext.delete(day)
        try? modelContext.save()

        if days.count <= 1 {
            isEditingDays = false
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

private struct ReviewDayDetailView: View {
    let day: VocabularyDay

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speechPlayer = DaySpeechPlayer()
    @State private var selectedWordIDs: Set<UUID> = []
    @State private var hidesKoreanMeaning = true
    @State private var showsWordDetails = false
    @State private var randomWordIDs: [UUID] = []

    private var reviewWords: [VocaWord] {
        let dayWords = day.wordList
        let wordsByID = Dictionary(uniqueKeysWithValues: dayWords.map { ($0.id, $0) })
        let orderedWords = randomWordIDs.compactMap { wordsByID[$0] }
        let missingWords = dayWords
            .filter { !randomWordIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        return orderedWords + missingWords
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WordDataTable(
                        title: "\(day.title) Review",
                        words: reviewWords,
                        hideKoreanMeaning: hidesKoreanMeaning,
                        allowsSelection: true,
                        showsTitle: false,
                        showsWordDetails: showsWordDetails,
                        revealsHiddenKoreanWhilePressing: true,
                        onEnglishLongPress: { word in
                            speechPlayer.speakEnglishWord(word.english)
                        },
                        selectedWordIDs: $selectedWordIDs
                    )
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            submitBar
        }
        .background(AppTheme.background)
        .navigationTitle(day.title)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            syncRandomOrder()
        }
        .onChange(of: day.wordList.map(\.id)) { _, _ in
            syncRandomOrder()
        }
        .onDisappear {
            speechPlayer.stop()
        }
    }

    private var submitBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                Text("\(selectedWordIDs.count) selected as Again")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    finishReview()
                } label: {
                    Label("Finish Review", systemImage: "checkmark.circle")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(reviewWords.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .background(.regularMaterial)
    }

    private func shuffleWords() {
        randomWordIDs = day.wordList.map(\.id).shuffled()
        selectedWordIDs = []
    }

    private func syncRandomOrder() {
        let dayWordIDs = day.wordList.map(\.id)
        let currentIDs = Set(dayWordIDs)

        if randomWordIDs.isEmpty {
            randomWordIDs = dayWordIDs.shuffled()
        } else {
            let orderedIDs = randomWordIDs.filter { currentIDs.contains($0) }
            let missingIDs = dayWordIDs.filter { !orderedIDs.contains($0) }.shuffled()
            randomWordIDs = orderedIDs + missingIDs
        }

        selectedWordIDs = selectedWordIDs.intersection(currentIDs)
    }

    private func finishReview() {
        guard !reviewWords.isEmpty else { return }

        let now = Date()

        for word in reviewWords {
            if selectedWordIDs.contains(word.id) {
                ReviewScheduler.markAgain(word, now: now)
            } else {
                ReviewScheduler.markKnown(word, now: now)
            }
        }

        day.reviewSessionCount += 1
        day.reviewedWordCount += reviewWords.count
        day.lastReviewedAt = now

        try? modelContext.save()
        selectedWordIDs = []
        dismiss()
    }

    private func deleteSelectedWords() {
        let selectedIDs = selectedWordIDs
        guard !selectedIDs.isEmpty else { return }

        speechPlayer.stop()

        for word in day.wordList where selectedIDs.contains(word.id) {
            day.removeWord(word)
            modelContext.delete(word)
        }

        randomWordIDs.removeAll { selectedIDs.contains($0) }
        selectedWordIDs.removeAll()
        try? modelContext.save()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Text("\(reviewWords.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                detailToggle
                koreanVisibilityButton
                shuffleButton
                deleteButton
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More Actions")
            .disabled(reviewWords.isEmpty)
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            Text("\(reviewWords.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            detailToggle
            koreanVisibilityButton
            shuffleButton
            deleteButton
        }
        #endif
    }

    private var detailToggle: some View {
        Toggle(isOn: $showsWordDetails) {
            Label(showsWordDetails ? "Hide Word Details" : "Show Word Details", systemImage: "text.justify")
        }
        .toggleStyle(.button)
        .disabled(reviewWords.isEmpty)
    }

    private var koreanVisibilityButton: some View {
        Button {
            hidesKoreanMeaning.toggle()
        } label: {
            Label(hidesKoreanMeaning ? "Show Korean" : "Hide Korean", systemImage: hidesKoreanMeaning ? "eye.slash" : "eye")
        }
    }

    private var shuffleButton: some View {
        Button {
            shuffleWords()
        } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleteSelectedWords()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(selectedWordIDs.isEmpty)
    }
}

#Preview {
    NavigationStack {
        ReviewView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
