import SwiftData
import SwiftUI

struct ReviewView: View {
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]

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
                            NavigationLink {
                                ReviewDayDetailView(day: day)
                            } label: {
                                DayCardView(day: day, isSelected: false)
                            }
                            .buttonStyle(.plain)
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
    }
}

private struct ReviewDayDetailView: View {
    let day: VocabularyDay

    @Environment(\.modelContext) private var modelContext
    @State private var selectedWordIDs: Set<UUID> = []
    @State private var hidesKoreanMeaning = true
    @State private var randomWordIDs: [UUID] = []

    private var reviewWords: [VocaWord] {
        let wordsByID = Dictionary(uniqueKeysWithValues: day.words.map { ($0.id, $0) })
        let orderedWords = randomWordIDs.compactMap { wordsByID[$0] }
        let missingWords = day.words
            .filter { !randomWordIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        return orderedWords + missingWords
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(macOS)
                    reviewControls
                    #endif

                    WordDataTable(
                        title: "\(day.title) Review",
                        words: reviewWords,
                        hideKoreanMeaning: hidesKoreanMeaning,
                        allowsSelection: true,
                        showsTitle: false,
                        selectedWordIDs: $selectedWordIDs
                    )
                }
                #if os(iOS)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                #else
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 840, alignment: .topLeading)
                #endif
                .frame(maxWidth: .infinity, alignment: .top)
            }

            submitBar
        }
        .background(AppTheme.background)
        .navigationTitle(day.title)
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
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
            #endif
        }
        .onAppear {
            syncRandomOrder()
        }
        .onChange(of: day.words.map(\.id)) { _, _ in
            syncRandomOrder()
        }
    }

    private var reviewControls: some View {
        HStack(spacing: 12) {
            Toggle("Hide Korean", isOn: $hidesKoreanMeaning)
                .toggleStyle(.switch)

            Spacer()

            Button {
                shuffleWords()
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .calmCard()
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
        randomWordIDs = day.words.map(\.id).shuffled()
        selectedWordIDs = []
    }

    private func syncRandomOrder() {
        let currentIDs = Set(day.words.map(\.id))

        if randomWordIDs.isEmpty {
            randomWordIDs = day.words.map(\.id).shuffled()
        } else {
            let orderedIDs = randomWordIDs.filter { currentIDs.contains($0) }
            let missingIDs = day.words.map(\.id).filter { !orderedIDs.contains($0) }.shuffled()
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
}

#Preview {
    NavigationStack {
        ReviewView()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
