import Charts
import SwiftUI

/// 예측: 앞으로의 학습 부하와 권장 새 단어 속도.
struct StatsForecastSection: View {
    enum Scenario: String, CaseIterable, Identifiable {
        case mine = "내 정답률"
        case perfect = "모두 정답"
        var id: Self { self }
    }

    let stats: StudyStats
    let history: ReviewHistoryStats

    @State private var horizon = 30
    @State private var scenario: Scenario = .mine
    @State private var newWordsPerDay: Double = 5
    @State private var recommended: Int?

    /// 기록이 없으면 보통 학습자 가정 (85% / 재도전 80%).
    private var accuracy: (p: Double, q: Double) {
        switch scenario {
        case .perfect: (1, 1)
        case .mine: (history.firstSessionAccuracy ?? 0.85, history.retryAccuracy ?? 0.8)
        }
    }

    private var forecast: SRSForecaster.Result {
        SRSForecaster.run(.init(
            cards: stats.words.map(\.card),
            currentLearningDay: stats.currentLearningDay,
            days: horizon,
            accuracy: accuracy.p,
            retryAccuracy: accuracy.q,
            newWordsPerDay: newWordsPerDay
        ))
    }

    var body: some View {
        let forecast = forecast
        VStack(alignment: .leading, spacing: 16) {
            controls
            verdict(forecast)
            loadChart(forecast)
            bucketChart(forecast)
            nextDays(forecast)
        }
        .task(id: "\(scenario.rawValue)|\(stats.words.count)|\(stats.currentLearningDay)") {
            let cards = stats.words.map(\.card)
            let day = stats.currentLearningDay
            let (p, q) = accuracy
            recommended = await Task.detached(priority: .userInitiated) {
                SRSForecaster.recommendedNewWordsPerDay(cards: cards, currentLearningDay: day, accuracy: p, retryAccuracy: q)
            }.value
        }
    }

    private var controls: some View {
        StatsCard(title: "예측 조건") {
            Picker("시나리오", selection: $scenario) {
                ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(scenario == .perfect
                 ? "모든 문제를 맞힌다고 가정해요 (가장 적은 부하)."
                 : "1차 정답률 \(percentText(accuracy.p)), 재도전 정답률 \(percentText(accuracy.q))\(history.firstSessionAccuracy == nil ? " (기록이 없어 기본값)" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("학습일마다 새 단어")
                    Spacer()
                    Text("\(Int(newWordsPerDay))개").font(.body.monospacedDigit().weight(.semibold))
                }
                Slider(value: $newWordsPerDay, in: 0...30, step: 1)
                if let recommended {
                    Button {
                        newWordsPerDay = Double(recommended)
                    } label: {
                        Label("권장: 학습일당 \(recommended)개 이하 (180학습일 동안 \(SRSEngine.dailyReviewLimit)개 안 넘음)", systemImage: "lightbulb")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            Picker("기간", selection: $horizon) {
                Text("30학습일").tag(30)
                Text("60학습일").tag(60)
                Text("180학습일").tag(180)
            }
            .pickerStyle(.segmented)
        }
    }

    private func verdict(_ forecast: SRSForecaster.Result) -> some View {
        let overflow = forecast.firstOverflowOffset
        let tint: Color = overflow == nil ? .green : .red
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: overflow == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                if let overflow {
                    Text("\(overflow == 0 ? "오늘" : "\(overflow)학습일 뒤")부터 하루 \(SRSEngine.dailyReviewLimit)개를 넘어요")
                        .font(.headline)
                    Text("약 \(history.estimatedDate(afterLearningDays: overflow).formatted(.dateTime.month().day())) 무렵. 넘친 단어는 다음 학습으로 밀리고, 새 단어가 먼저 나와서 복습이 늦어져요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(horizon)학습일 동안 하루 \(SRSEngine.dailyReviewLimit)개 안에 들어와요")
                        .font(.headline)
                    Text("가장 많은 날 약 \(Int(forecast.peakDue.rounded()))개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }

    private func loadChart(_ forecast: SRSForecaster.Result) -> some View {
        StatsCard(title: "학습일별 예상 문제 수", subtitle: "빨간 부분은 상한을 넘어 다음으로 밀리는 단어") {
            Chart {
                ForEach(forecast.days) { day in
                    BarMark(x: .value("학습일", day.offset), y: .value("문제", day.served))
                        .foregroundStyle(Color.accentColor)
                    if day.backlog > 0.5 {
                        BarMark(x: .value("학습일", day.offset), y: .value("밀림", day.backlog))
                            .foregroundStyle(Color.red.opacity(0.75))
                    }
                }
                RuleMark(y: .value("하루 상한", SRSEngine.dailyReviewLimit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red)
                    .annotation(position: .top, alignment: .leading) {
                        Text("상한 \(SRSEngine.dailyReviewLimit)").font(.caption2).foregroundStyle(.red)
                    }
            }
            .chartXAxisLabel("오늘부터 학습일")
            .frame(height: 200)
        }
    }

    private func bucketChart(_ forecast: SRSForecaster.Result) -> some View {
        StatsCard(title: "구간별 단어 수 변화", subtitle: "새 단어가 장기 기억으로 옮겨 가는 예상") {
            Chart {
                ForEach(forecast.days) { day in
                    ForEach(StageBucket.allCases) { bucket in
                        AreaMark(
                            x: .value("학습일", day.offset),
                            y: .value("단어", day.buckets[bucket] ?? 0),
                            stacking: .standard
                        )
                        .foregroundStyle(by: .value("구간", bucket.title))
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: StageBucket.allCases.map(\.title),
                range: StageBucket.allCases.map(\.color)
            )
            .chartXAxisLabel("오늘부터 학습일")
            .frame(height: 200)
        }
    }

    private func nextDays(_ forecast: SRSForecaster.Result) -> some View {
        StatsCard(title: "다가오는 7학습일", subtitle: "예상 날짜는 최근 학습 속도(하루 \(String(format: "%.1f", history.learningDaysPerCalendarDay))학습일) 기준") {
            VStack(spacing: 0) {
                ForEach(forecast.days.prefix(7)) { day in
                    HStack {
                        Text(day.offset == 0 ? "오늘" : "학습일 +\(day.offset)")
                            .font(.subheadline.weight(.medium))
                        Text(history.estimatedDate(afterLearningDays: day.offset).formatted(.dateTime.month().day().weekday(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(day.served.rounded()))문제")
                            .font(.subheadline.monospacedDigit())
                        if day.isOverflow {
                            Text("+\(Int(day.backlog.rounded())) 밀림")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 7)
                    Divider().opacity(0.4)
                }
            }
        }
    }
}
