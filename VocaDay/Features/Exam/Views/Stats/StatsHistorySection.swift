import Charts
import SwiftUI

/// 기록: 풀이 로그 기반 추이.
struct StatsHistorySection: View {
    let history: ReviewHistoryStats
    let wordsByID: [UUID: VocaWord]

    var body: some View {
        if history.isEmpty {
            EmptyStateView(title: "시험을 보면 기록이 쌓여요. 학습일별 정답률과 유형별 정답률을 여기서 볼 수 있어요.", systemImage: "clock.arrow.circlepath")
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                summary
                dailyVolume
                dailyAccuracy
                modeAccuracy
                recentSessions
            }
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            StatTile(title: "푼 문제", value: "\(history.entries.count)", caption: "세션 \(history.sessions.count)번")
            StatTile(title: "1차 정답률", value: percentText(history.firstSessionAccuracy), tint: .accentColor)
            StatTile(title: "재도전 정답률", value: percentText(history.retryAccuracy))
            StatTile(title: "연속 학습", value: "\(history.calendarStreak)일")
        }
    }

    private var dailyVolume: some View {
        let points = Array(history.dailyPoints.suffix(30))
        return StatsCard(title: "학습일별 문제 수", subtitle: "최근 30학습일") {
            Chart(points) { point in
                BarMark(x: .value("학습일", "\(point.learningDay + 1)"), y: .value("정답", point.correct))
                    .foregroundStyle(Color.green.gradient)
                BarMark(x: .value("학습일", "\(point.learningDay + 1)"), y: .value("오답", point.total - point.correct))
                    .foregroundStyle(Color.red.opacity(0.7))
            }
            .chartXAxisLabel("학습일")
            .frame(height: 170)
            HStack(spacing: 12) {
                Label("정답", systemImage: "circle.fill").foregroundStyle(.green)
                Label("오답", systemImage: "circle.fill").foregroundStyle(.red)
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)
        }
    }

    private var dailyAccuracy: some View {
        let points = Array(history.dailyPoints.suffix(30))
        return StatsCard(title: "정답률 추이") {
            Chart(points) { point in
                LineMark(x: .value("학습일", point.learningDay + 1), y: .value("정답률", point.accuracy * 100))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("학습일", point.learningDay + 1), y: .value("정답률", point.accuracy * 100))
                    .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxisLabel("학습일")
            .frame(height: 160)
        }
    }

    private var modeAccuracy: some View {
        StatsCard(title: "유형별 정답률", subtitle: "어떤 문제 유형이 약한지") {
            Chart(history.modeAccuracies) { item in
                BarMark(x: .value("정답률", item.accuracy * 100), y: .value("유형", item.mode.displayName))
                    .foregroundStyle(Color.accentColor.gradient)
                    .annotation(position: .trailing) {
                        Text("\(percentText(item.accuracy)) · \(item.total)문제")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 0...100)
            .frame(height: CGFloat(max(history.modeAccuracies.count, 1)) * 40 + 20)
        }
    }

    private var recentSessions: some View {
        StatsCard(title: "최근 세션") {
            VStack(spacing: 0) {
                ForEach(history.sessions.prefix(15)) { session in
                    HStack {
                        Image(systemName: session.kind == .retry ? "arrow.counterclockwise.circle" : "checkmark.seal")
                            .foregroundStyle(session.kind == .retry ? .orange : .accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("학습일 \(session.learningDay + 1) · \(session.kind == .retry ? "재도전" : "오늘의 학습")")
                                .font(.subheadline.weight(.medium))
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(session.correct)/\(session.total)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    .padding(.vertical, 8)
                    Divider().opacity(0.4)
                }
            }
        }
    }
}
