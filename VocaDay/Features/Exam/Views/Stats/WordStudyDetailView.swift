import Charts
import SwiftUI

/// 단어 한 개의 학습 상태·앞으로 경로·풀이 이력. 읽기 전용 (편집은 단어장에서).
struct WordStudyDetailView: View {
    let word: VocaWord
    let stats: StudyStats
    let history: ReviewHistoryStats

    var body: some View {
        let statsWord = word.statsWord
        let quiz = word.quizWord
        let entries = history.history(for: word.id)
        let path = SRSForecaster.projectedPath(for: word.srsCard, currentLearningDay: stats.currentLearningDay)

        AppCollectionPage(maxContentWidth: 720, horizontalPadding: 20, verticalPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header(statsWord, quiz: quiz)
                status(statsWord, entries: entries)
                projection(path)
                historyList(entries)
                if quiz.isEnriched {
                    quizData(quiz)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(statsWord.term)
    }

    private func header(_ statsWord: StatsWord, quiz: QuizWord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(statsWord.term).font(.largeTitle.weight(.bold))
                Spacer()
                StageBadge(stage: statsWord.card.stage)
            }
            Text(statsWord.meaningKo).font(.title3)
            if !statsWord.dayTitle.isEmpty {
                Label(statsWord.dayTitle, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func status(_ statsWord: StatsWord, entries: [ReviewLogEntry]) -> some View {
        let until = stats.learningDaysUntilNext(statsWord)
        let correct = entries.filter(\.isCorrect).count
        return VStack(alignment: .leading, spacing: 12) {
            StatsCard(title: "단계 \(statsWord.card.stage) / \(SRSEngine.maxStage) · \(statsWord.bucket.title)") {
                HStack(spacing: 3) {
                    ForEach(0...SRSEngine.maxStage, id: \.self) { stage in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(stage <= statsWord.card.stage && statsWord.card.stage > 0
                                  ? StageBucket.of(stage: stage).color
                                  : AppTheme.raisedBackground)
                            .frame(height: 10)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                StatTile(
                    title: "다음 복습",
                    value: learningDayText(until),
                    caption: until == 0 ? "오늘 세션 대상" : "약 \(history.estimatedDate(afterLearningDays: until).formatted(.dateTime.month().day()))"
                )
                StatTile(title: "틀린 횟수", value: "\(statsWord.card.idkCount)", tint: statsWord.card.idkCount > 0 ? .red : .primary)
                StatTile(title: "시험 기록", value: entries.isEmpty ? "–" : "\(correct)/\(entries.count)", caption: entries.isEmpty ? "아직 없음" : "정답/전체")
                StatTile(title: "문제 준비", value: statsWord.isEnriched ? "완료" : "기본", caption: statsWord.isEnriched ? "4가지 유형 모두" : "짝 맞추기·한→영만")
            }
        }
    }

    private func projection(_ path: [SRSForecaster.PathPoint]) -> some View {
        let start = stats.currentLearningDay
        let reachTop = path.first { $0.stage == SRSEngine.maxStage }
        return StatsCard(
            title: "계속 맞힌다면",
            subtitle: reachTop.map { "\($0.learningDay - start)학습일 뒤 stage 10 (약 \(history.estimatedDate(afterLearningDays: $0.learningDay - start).formatted(.dateTime.year().month().day()))). 틀리면 한 단계 내려가고 간격이 짧아져요." }
        ) {
            Chart(Array(path.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("학습일", point.learningDay - start), y: .value("단계", point.stage))
                    .interpolationMethod(.stepEnd)
                PointMark(x: .value("학습일", point.learningDay - start), y: .value("단계", point.stage))
                    .foregroundStyle(StageBucket.of(stage: point.stage).color)
            }
            .chartYScale(domain: 0...SRSEngine.maxStage)
            .chartXAxisLabel("오늘부터 학습일")
            .frame(height: 170)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(path.prefix(10).enumerated()), id: \.offset) { _, point in
                        VStack(spacing: 2) {
                            Text(point.learningDay - start == 0 ? "오늘" : "+\(point.learningDay - start)")
                                .font(.caption2.monospacedDigit())
                            StageBadge(stage: point.stage)
                        }
                    }
                }
            }
        }
    }

    private func historyList(_ entries: [ReviewLogEntry]) -> some View {
        StatsCard(title: "풀이 이력", subtitle: entries.isEmpty ? "통계 기록을 시작한 뒤로 이 단어를 푼 적이 없어요." : nil) {
            VStack(spacing: 0) {
                ForEach(Array(entries.prefix(30).enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.isCorrect ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.mode?.displayName ?? "문제")\(entry.sessionKind == .retry ? " · 재도전" : "")\(detailText(entry.outcomeDetail))")
                                .font(.subheadline)
                            Text("학습일 \(entry.learningDay + 1) · \(entry.answeredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.stageBefore) → \(entry.stageAfter)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func detailText(_ detail: String) -> String {
        switch detail {
        case "typo": " · 오타"
        case "nearMiss": " · 다시 쓰기"
        default: ""
        }
    }

    private func quizData(_ quiz: QuizWord) -> some View {
        StatsCard(title: "시험 문제 데이터") {
            VStack(alignment: .leading, spacing: 8) {
                row("품사·수준", "\(quiz.pos) · \(quiz.cefr)")
                if !quiz.disambiguationKo.isEmpty { row("구분", quiz.disambiguationKo) }
                row("빈칸 문장", quiz.clozeSentence.replacingOccurrences(of: "<>", with: "_____"))
                row("정답", quiz.clozeAnswer)
                let forms = WordEntry.formKeys.compactMap { key -> String? in
                    let value = quiz.form(key)
                    return value.isEmpty ? nil : "\(AnswerGrader.formLabels[key] ?? key) \(value)"
                }
                if !forms.isEmpty { row("활용형", forms.joined(separator: " · ")) }
                if !quiz.nearMiss.isEmpty { row("비슷한 말", quiz.nearMiss.joined(separator: ", ")) }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}
