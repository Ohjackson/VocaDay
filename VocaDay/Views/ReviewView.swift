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

    @Environment(\.modelContext) private var modelContext
    @State private var selectedWordIDs: Set<UUID> = []
    @State private var hidesKoreanMeaning = true
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
            ToolbarItemGroup(placement: toolbarPlacement) {
                Text("\(reviewWords.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    hidesKoreanMeaning.toggle()
                } label: {
                    Image(systemName: hidesKoreanMeaning ? "eye.slash" : "eye")
                }
                .accessibilityLabel(hidesKoreanMeaning ? "Show Korean" : "Hide Korean")

                Button {
                    shuffleWords()
                } label: {
                    Image(systemName: "shuffle")
                }
                .accessibilityLabel("Shuffle")
            }
        }
        .onAppear {
            syncRandomOrder()
        }
        .onChange(of: day.wordList.map(\.id)) { _, _ in
            syncRandomOrder()
        }
    }

    private var submitBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                Text("\(selectedWordIDs.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    submitSelectedWords()
                } label: {
                    Label("Submit", systemImage: "checkmark.circle")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedWordIDs.isEmpty)
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

    private func submitSelectedWords() {
        guard !selectedWordIDs.isEmpty else { return }

        for word in reviewWords where selectedWordIDs.contains(word.id) {
            word.wrongCount += 1
        }

        try? modelContext.save()
        selectedWordIDs = []
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

#Preview {
    NavigationStack {
        ReviewView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
