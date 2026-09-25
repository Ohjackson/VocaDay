import SwiftData
import SwiftUI

/// "통계" 탭: 현황 · 기록 · 예측 · 단어.
struct StudyStatsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "현황"
        case history = "기록"
        case forecast = "예측"
        case words = "단어"
        var id: Self { self }
    }

    @Query(sort: \VocaWord.createdAt) private var words: [VocaWord]
    @Query private var progressRecords: [StudyProgress]
    @Query(sort: \ReviewLog.answeredAt) private var logs: [ReviewLog]

    @State private var section: Section = .overview

    private var stats: StudyStats {
        StudyStats(
            words: words.map(\.statsWord),
            session: StudyProgressStore.preferred(progressRecords)?.sessionState ?? .initial
        )
    }

    private var history: ReviewHistoryStats {
        ReviewHistoryStats(entries: logs.map(\.entry))
    }

    var body: some View {
        let stats = stats
        let history = history
        AppCollectionPage(maxContentWidth: 840, horizontalPadding: 20, verticalPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("통계 보기", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if words.isEmpty {
                    EmptyStateView(title: "단어를 추가하면 학습 통계가 보여요.", systemImage: "chart.bar.xaxis")
                        .padding(.top, 40)
                } else {
                    switch section {
                    case .overview:
                        StatsOverviewSection(stats: stats, history: history, wordsByID: wordsByID)
                    case .history:
                        StatsHistorySection(history: history, wordsByID: wordsByID)
                    case .forecast:
                        StatsForecastSection(stats: stats, history: history)
                    case .words:
                        StatsWordListSection(stats: stats, history: history, wordsByID: wordsByID)
                    }
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle("통계")
    }

    private var wordsByID: [UUID: VocaWord] {
        Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
