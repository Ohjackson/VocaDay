import Charts
import SwiftUI

/// 현황: 지금 상태 한눈에 보기.
struct StatsOverviewSection: View {
    let stats: StudyStats
    let history: ReviewHistoryStats
    let wordsByID: [UUID: VocaWord]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                kpis(now: context.date)
            }
            stageHistogram
            bucketDonut
            upcomingSchedule
            if stats.dayBreakdowns.count > 0 {
                dayBreakdown
            }
            hardestWords
        }
    }

    // MARK: KPI

    private func kpis(now: Date) -> some View {
        let status = SRSEngine.sessionStatus(for: stats.session, now: now)
        let retryCaption: String? = {
            switch status {
            case .waitingForRetry(let remaining, _): "재도전까지 \(remaining)"
            case .readyForRetry: "지금 재도전 가능"
            case .readyForFirstSession: nil
            }
        }()
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(title: "전체 단어", value: "\(stats.words.count)", caption: "보강 \(stats.enrichedCount)개")
            StatTile(title: "오늘 복습", value: "\(stats.dueTodayIDs.count)", caption: "하루 최대 \(SRSEngine.dailyReviewLimit)개", tint: .accentColor)
            StatTile(
                title: "밀린 단어",
                value: "\(stats.backlogCount)",
                caption: stats.backlogCount > 0 ? "다음 학습에 먼저 나와요" : "밀린 단어 없음",
                tint: stats.backlogCount > 0 ? .red : .primary
            )
            StatTile(title: "재도전 대기", value: "\(stats.retryPendingCount)", caption: retryCaption ?? "없음", tint: stats.retryPendingCount > 0 ? .orange : .primary)
            StatTile(title: "학습일", value: "\(stats.currentLearningDay + 1)", caption: "세션을 끝내면 +1")
            StatTile(title: "연속 학습", value: "\(history.calendarStreak)일", caption: "정답률 \(percentText(history.overallAccuracy))")
        }
    }

    // MARK: 분포

    private var stageHistogram: some View {
        let histogram = stats.stageHistogram
        return StatsCard(title: "단계별 단어 수", subtitle: "stage 0(처음) → 10(장기 기억). 맞히면 한 단계 오르고 틀리면 한 단계 내려가요.") {
            Chart(Array(histogram.enumerated()), id: \.offset) { stage, count in
                BarMark(x: .value("단계", "\(stage)"), y: .value("단어", count))
                    .foregroundStyle(StageBucket.of(stage: stage).color.gradient)
                    .annotation(position: .top) {
                        if count > 0 {
                            Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
            }
            .chartXAxisLabel("단계")
            .frame(height: 180)
            BucketLegend()
        }
    }

    private var bucketDonut: some View {
        let counts = stats.bucketCounts
        let total = max(stats.words.count, 1)
        return StatsCard(title: "학습 구간") {
            HStack(alignment: .center, spacing: 20) {
                Chart(StageBucket.allCases) { bucket in
                    SectorMark(
                        angle: .value("단어", counts[bucket] ?? 0),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(bucket.color)
                }
                .frame(width: 130, height: 130)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(Int((Double(counts[.longTerm] ?? 0) / Double(total) * 100).rounded()))%")
                            .font(.title3.weight(.bold))
                        Text("장기 기억").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(StageBucket.allCases) { bucket in
                        HStack {
                            Circle().fill(bucket.color).frame(width: 10, height: 10)
                            Text(bucket.title).font(.subheadline)
                            Text("stage \(bucket.stages.lowerBound)\(bucket.stages.count > 1 ? "–\(bucket.stages.upperBound)" : "")")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(counts[bucket] ?? 0)").font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var upcomingSchedule: some View {
        let counts = stats.scheduledCounts(nextLearningDays: 14)
        return StatsCard(title: "앞으로 14학습일 차례", subtitle: "지금 상태 그대로일 때 학습일마다 차례가 오는 단어 수 (새로 맞히거나 틀리면 바뀌어요).") {
            Chart(Array(counts.enumerated()), id: \.offset) { offset, count in
                BarMark(x: .value("학습일", offset == 0 ? "오늘" : "+\(offset)"), y: .value("단어", count))
                    .foregroundStyle(count > SRSEngine.dailyReviewLimit ? Color.red : Color.accentColor)
                RuleMark(y: .value("하루 상한", SRSEngine.dailyReviewLimit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(counts.max() ?? 0 > SRSEngine.dailyReviewLimit / 2 ? 0.6 : 0))
            }
            .frame(height: 160)
        }
    }

    private var dayBreakdown: some View {
        let days = stats.dayBreakdowns
        return StatsCard(title: "데이별 진도", subtitle: "각 데이 단어가 어느 구간에 있는지") {
            Chart {
                ForEach(days) { day in
                    ForEach(StageBucket.allCases) { bucket in
                        BarMark(x: .value("단어", day.counts[bucket] ?? 0), y: .value("데이", day.title))
                            .foregroundStyle(bucket.color)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: CGFloat(max(days.count, 1)) * 34 + 30)
            BucketLegend()
        }
    }

    private var hardestWords: some View {
        let hardest = stats.hardestWords()
        return StatsCard(title: "자주 틀리는 단어", subtitle: hardest.isEmpty ? "아직 틀린 단어가 없어요." : "틀린 횟수가 많은 순") {
            VStack(spacing: 0) {
                ForEach(hardest) { word in
                    if let vocaWord = wordsByID[word.id] {
                        NavigationLink(value: AppRoute.wordStudyDetail(wordID: vocaWord.id)) {
                            StatsWordRow(word: word, stats: stats)
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }
}

/// 단어 한 줄: 단어·뜻 / stage / 다음 복습 / 틀린 횟수.
struct StatsWordRow: View {
    let word: StatsWord
    let stats: StudyStats

    var body: some View {
        HStack(spacing: 12) {
            StageBadge(stage: word.card.stage)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.term).font(.body.weight(.semibold))
                Text(word.meaningKo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(learningDayText(stats.learningDaysUntilNext(word)))
                    .font(.caption.weight(.medium))
                if word.card.idkCount > 0 {
                    Text("틀림 \(word.card.idkCount)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}
