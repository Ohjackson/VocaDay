import SwiftData
import SwiftUI

/// 오늘의 기본 단어 검수. 후보를 한 장씩 "외울래요 / 이미 알아요"로 고르고, 확인하면 데이를 만든다.
/// "이미 알아요"로 뺀 단어는 데이에 넣지 않고 보관함(`SetAsideWord`)에 둔다.
struct BundledDayReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigate) private var navigate
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @Query private var setAsideWords: [SetAsideWord]

    @State private var review: BundledDayReview?
    @State private var loadMessage: String?
    @State private var errorAlert: VocaAlert?

    var body: some View {
        AppCollectionPage(maxContentWidth: 640, horizontalPadding: 20, verticalPadding: 24) {
            if let loadMessage {
                EmptyStateView(title: loadMessage, systemImage: "sparkles")
            } else if let review {
                if review.isComplete {
                    summary(review)
                } else if let word = review.current {
                    reviewCard(word, review: review)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("오늘의 새 단어")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppRoute.setAsideWords) {
                    Image(systemName: "archivebox")
                }
                .accessibilityLabel("보관함")
                .help("보관함")
            }
        }
        .onAppear(perform: startIfNeeded)
        .alert(item: $errorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    // MARK: 검수 카드

    private func reviewCard(_ word: VocaWordJSON, review: BundledDayReview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("외울 단어 \(review.kept.count) / \(review.targetCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("보관 \(review.setAside.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(review.kept.count), total: Double(max(review.targetCount, 1)))

            VStack(alignment: .leading, spacing: 14) {
                Text(word.english)
                    .font(.largeTitle.weight(.bold))
                    .textSelection(.enabled)
                Text(word.meaningKo)
                    .font(.title3)
                if !word.exampleEn.isEmpty {
                    Divider()
                    Text(word.exampleEn)
                        .font(.body)
                    Text(word.exampleKo)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !word.note.isEmpty {
                    Text(word.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.cardPadding)
            .calmCard()

            HStack(spacing: 12) {
                AppActionButton(title: "이미 알아요 · 보관", systemImage: "archivebox") {
                    self.review?.setAsideCurrent()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                AppActionButton(title: "외울래요", systemImage: "plus.circle", isProminent: true) {
                    self.review?.keep()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            HStack {
                Button("이전 카드", systemImage: "arrow.uturn.backward") {
                    self.review?.goBack()
                }
                .disabled(!review.canGoBack)
                Spacer()
                Button("나머지 모두 외울래요") {
                    self.review?.keepRemaining()
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)

            Text("'이미 알아요'로 뺀 단어는 단어장에 넣지 않고 보관함에 둬요. 뺀 만큼 다음 단어를 이어서 보여줘요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 요약

    private func summary(_ review: BundledDayReview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            AppActionButton(
                title: "OK · \(DayFactory.nextDayTitle(existingDays: days)) 만들기",
                systemImage: "checkmark.circle",
                isProminent: true,
                isDisabled: review.kept.isEmpty
            ) {
                createDay(review)
            }

            Button("이전 카드로 돌아가기", systemImage: "arrow.uturn.backward") {
                self.review?.goBack()
            }
            .font(.subheadline)
            .buttonStyle(.borderless)

            wordSection(title: "외울 단어 \(review.kept.count)개", words: review.kept)
            if !review.setAside.isEmpty {
                wordSection(title: "보관할 단어 \(review.setAside.count)개", words: review.setAside)
            }
        }
    }

    private func wordSection(title: String, words: [VocaWordJSON]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    if index > 0 {
                        Divider()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.english)
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 12)
                        Text(word.meaningKo)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .calmCard()
        }
    }

    // MARK: 동작

    private func startIfNeeded() {
        guard review == nil, loadMessage == nil else { return }
        if BundledWordPack.hasAddedToday(existingDays: days) {
            loadMessage = BundledWordPackError.alreadyAddedToday.localizedDescription
            return
        }
        do {
            let candidates = BundledWordPack.candidates(
                from: try BundledWordPack.loadWords(),
                existingDays: days,
                setAside: setAsideWords
            )
            guard !candidates.isEmpty else {
                loadMessage = BundledWordPackError.exhausted.localizedDescription
                return
            }
            review = BundledDayReview(candidates: candidates)
        } catch {
            loadMessage = error.localizedDescription
        }
    }

    private func createDay(_ review: BundledDayReview) {
        do {
            let day = try BundledWordPack.addDay(
                kept: review.kept,
                setAside: review.setAside,
                existingDays: days,
                in: modelContext
            )
            navigate(.dayWords(dayID: day.id), replacingTop: true)
        } catch {
            errorAlert = VocaAlert(title: "단어장을 만들 수 없어요", message: error.localizedDescription)
        }
    }
}
