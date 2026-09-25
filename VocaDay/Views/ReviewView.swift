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

/// "복습" 탭. 오늘 복습할 단어는 시험과 같은 SRS 대기열(`StudyQueue`)에서 가져온다.
struct ReviewView: View {
    @Query(sort: \VocabularyDay.createdAt) private var days: [VocabularyDay]
    @Query(sort: \VocaWord.createdAt) private var words: [VocaWord]
    @Query private var progressRecords: [StudyProgress]
    /// 장부가 바뀌면(복습·시험 기록) 화면을 다시 그린다.
    @AppStorage(StudyDayLedgerStore.storageKey) private var ledgerData: Data?
    @State private var scope: ReviewListScope = .due

    private var snapshot: StudyQueueSnapshot {
        _ = ledgerData
        return StudyQueue.snapshot(words: words, progress: StudyProgressStore.preferred(progressRecords))
    }

    var body: some View {
        let snapshot = snapshot
        let remaining = Set(snapshot.remainingIDs)
        let dueDays = days.filter { dueCount(for: $0, remaining: remaining) > 0 }
        let displayedDays = scope == .due ? dueDays : days

        AppCollectionPage(
            maxContentWidth: 840,
            horizontalPadding: 20,
            verticalPadding: 24
        ) {
            VStack(alignment: .leading, spacing: 18) {
                reviewSummary(snapshot: snapshot, dueDayCount: dueDays.count)
                LearningMethodCard()

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
                            reviewDayRow(for: day, dueCount: dueCount(for: day, remaining: remaining))
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

    private func reviewSummary(snapshot: StudyQueueSnapshot, dueDayCount: Int) -> some View {
        let dueWordCount = snapshot.remainingCount
        return HStack(spacing: 14) {
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
                    Text(snapshot.kind == .retry
                         ? "재도전: 틀렸던 단어를 다시 확인해요. 여기서 풀거나 시험으로 풀어도 같은 기록이 돼요."
                         : "\(dueDayCount)개 데이에 있어요. 여기서 풀거나 시험으로 풀어도 같은 기록이 돼요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if snapshot.isDoneForToday {
                    Text(snapshot.upcomingCount > 0
                         ? "다음 복습(단어 \(snapshot.upcomingCount)개)은 내일 열려요. 간격을 두어야 오래 기억해요."
                         : "오늘 학습을 마쳤어요. 내일 다시 만나요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if case .waitingForRetry(let remainingTime, _) = snapshot.status {
                    Text("틀린 단어의 재도전은 \(remainingTime) 뒤에 열려요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !words.isEmpty {
                    Text("다음 학습일에 복습할 단어를 다시 불러올게요.")
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

    private func reviewDayRow(for day: VocabularyDay, dueCount: Int) -> some View {
        let dueOnly = scope == .due

        return NavigationLink(value: AppRoute.reviewSession(dayID: day.id, dueOnly: dueOnly)) {
            DayCardView(
                day: day,
                isSelected: false,
                dueReviewCount: dueCount
            )
        }
        .buttonStyle(.plain)
    }

    private func dueCount(for day: VocabularyDay, remaining: Set<UUID>) -> Int {
        day.wordList.filter { remaining.contains($0.id) }.count
    }
}

#Preview {
    NavigationStack {
        ReviewView()
            .appRouteDestinations()
    }
    .modelContainer(for: [VocabularyDay.self, VocaWord.self], inMemory: true)
}
