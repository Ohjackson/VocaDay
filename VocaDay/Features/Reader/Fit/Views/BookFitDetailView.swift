import SwiftUI

/// 적합도 상세: 요약, 장별 표, 복습 단어, 토익 단어, 모르는 단어, 주제, 품질 경고, 출처.
/// 스크롤 본문만 만든다. 내비게이션(push)과 제목은 붙이는 쪽에서 정한다 (macOS 본문 열 / iPhone 스택 공통).
struct BookFitDetailView: View {
    let report: BookFitReport
    /// 주제 분류 단추를 보일지 (기기 안 모델이 있을 때만 넘긴다).
    var onClassifyTopics: (() -> Void)?
    var isClassifyingTopics = false

    var body: some View {
        ScrollView {
            BookFitDetailSections(report: report, onClassifyTopics: onClassifyTopics, isClassifyingTopics: isClassifyingTopics)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.pageHorizontalPadding)
                .padding(.vertical, AppTheme.pageVerticalPadding)
        }
        .background(AppTheme.background)
    }
}

/// 상세 화면의 카드들 (스크롤 없이). 다른 화면 안에 넣을 때도 쓴다.
struct BookFitDetailSections: View {
    let report: BookFitReport
    var onClassifyTopics: (() -> Void)?
    var isClassifyingTopics = false

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                chapterCard
                if !report.reviewWords.isEmpty {
                    wordCard(title: "복습 단어 재등장", caption: "외우는 중인 단어가 책에 다시 나와요.", words: report.reviewWords, tint: .purple)
                }
                if !report.examWords.isEmpty {
                    wordCard(title: "토익 단어 \(report.overall.examTypeCount)종", caption: "1,000단어당 \(BookFitFormat.perThousand(report.overall.examPerThousand))회", words: Array(report.examWords.prefix(40)), tint: .blue)
                }
                if !report.unknownWords.isEmpty {
                    wordCard(title: "모르는 단어", caption: "단어장에도 고빈도 목록에도 없는 단어, 많이 나온 순", words: report.unknownWords, tint: .orange)
                }
                topicCard
                qualityCard
                sourceFooter
            }
    }

    // MARK: 요약

    private var summaryCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text(report.bookTitle)
                    .font(.headline)
                Spacer()
                BookFitVerdictPill(verdict: report.verdict)
            }
            Text(report.verdict.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                metric("아는 단어", BookFitFormat.percent(report.overall.coverage))
                metric("모르는 단어", "1,000당 \(BookFitFormat.perThousand(report.overall.unknownPerThousand))")
                metric("평균 문장", String(format: "%.1f단어", report.overall.averageSentenceLength))
            }

            CoverageBar(coverage: report.overall.coverage, criteria: report.criteria)

            Text("센 단어 \(BookFitFormat.number(report.overall.tokenCount))개 (이름 \(report.overall.properNounCount)·숫자 \(report.overall.numberCount)개 제외) · 문장 \(report.overall.sentenceCount)개")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("아는 단어 = 고빈도 상위 \(BookFitFormat.number(report.generalKnownCount))개 + 단어장에서 익숙해진 단어 · 기준 \(BookFitFormat.percent(report.criteria.extensiveCoverage, digits: 0)) 이상 다독용, \(BookFitFormat.percent(report.criteria.intensiveCoverage, digits: 0)) 이상 정독용")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.raisedBackground, in: RoundedRectangle(cornerRadius: AppTheme.innerCornerRadius))
    }

    // MARK: 장별

    private var chapterCard: some View {
        card {
            Text("장별")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("장")
                    Text("아는 단어").gridColumnAlignment(.trailing)
                    Text("모름/1000").gridColumnAlignment(.trailing)
                    Text("토익").gridColumnAlignment(.trailing)
                    Text("판정")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(report.chapters) { chapter in
                    GridRow {
                        HStack(spacing: 4) {
                            Text("\(chapter.index + 1). \(chapter.title)")
                                .lineLimit(1)
                            if chapter.id == report.hardestChapter?.id, report.chapters.count > 1 {
                                Image(systemName: "flag.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("가장 어려운 장")
                            }
                        }
                        Text(BookFitFormat.percent(chapter.stats.coverage)).monospacedDigit()
                        Text(BookFitFormat.perThousand(chapter.stats.unknownPerThousand)).monospacedDigit()
                        Text("\(chapter.stats.examTypeCount)종").monospacedDigit()
                        BookFitVerdictPill(verdict: chapter.stats.verdict)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: 단어

    private func wordCard(title: String, caption: String, words: [FitWordCount], tint: Color) -> some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            WordChipFlow(words: words, tint: tint)
        }
    }

    // MARK: 주제

    @ViewBuilder
    private var topicCard: some View {
        if let topics = report.topics {
            card {
                HStack(alignment: .firstTextBaseline) {
                    Text("주제").font(.headline)
                    Spacer()
                    Text("토익 상황 \(BookFitFormat.percent(topics.examSituationShare, digits: 0))")
                        .font(.subheadline.weight(.medium))
                }
                ForEach(Array(topics.chapters.enumerated()), id: \.offset) { index, topic in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)장").font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                        if let topic {
                            Image(systemName: topic.isExamSituation ? "briefcase.fill" : "book")
                                .foregroundStyle(topic.isExamSituation ? .blue : .secondary)
                            Text(topic.situation.isEmpty ? "—" : topic.situation)
                            Spacer()
                            Text(topic.genres.map(\.title).joined(separator: "·"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("분류하지 못했어요").foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        } else if let onClassifyTopics {
            card {
                Text("주제").font(.headline)
                Text("기기 안 모델로 장마다 토익 상황인지, 어떤 글 형식인지 나눠 볼 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onClassifyTopics) {
                    if isClassifyingTopics {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("주제 분류하기", systemImage: "sparkles")
                    }
                }
                .disabled(isClassifyingTopics)
            }
        }
    }

    // MARK: 품질

    private var qualityCard: some View {
        card {
            Text("품질 점검").font(.headline)
            ForEach(report.quality) { warning in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: warning.count == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(warning.count == 0 ? Color.green : Color.orange)
                        Text(warning.kind.title)
                        Spacer()
                        Text(warning.kind == .garbledText && report.garbledRatio > 0
                             ? "\(warning.count)문장 · \(BookFitFormat.percent(report.garbledRatio, digits: 2))"
                             : "\(warning.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    if warning.count > 0 {
                        Text(describe(warning))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.leading, 26)
                    }
                }
            }
        }
    }

    private func describe(_ warning: BookQualityWarning) -> String {
        switch warning.kind {
        case .glossaryPositionInvalid, .glossaryPositionNotFirst:
            zip(warning.details, warning.positions).map { "\($0) (\(BookFitFormat.position($1)))" }.joined(separator: ", ")
        case .garbledText:
            warning.positions.prefix(5).map(BookFitFormat.position).joined(separator: ", ")
        default:
            warning.positions.prefix(5).map(BookFitFormat.position).joined(separator: ", ")
                + (warning.count > 5 ? " 외 \(warning.count - 5)곳" : "")
        }
    }

    // MARK: 출처

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("기준 단어 목록: \(report.referenceSources.joined(separator: " · "))")
            Text("NGSL (Browne, Culligan & Phillips, 2013), TSL (Browne & Culligan, 2016) · newgeneralservicelist.com · CC BY-SA 4.0")
            Text("판정 기준: Hu & Nation (2000)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(AppTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .calmCard()
    }
}

/// 아는 단어 비율 막대. 정독·다독 기준선을 함께 그린다. 80%~100% 구간만 보여 차이가 보이게 한다.
private struct CoverageBar: View {
    let coverage: Double
    let criteria: BookFitCriteria
    private let lower = 0.8

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        CGFloat((min(max(value, lower), 1) - lower) / (1 - lower)) * width
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.raisedBackground)
                Capsule().fill(BookFitFormat.color(criteria.verdict(coverage: coverage)))
                    .frame(width: max(x(coverage, width: proxy.size.width), 6))
                ForEach([criteria.intensiveCoverage, criteria.extensiveCoverage], id: \.self) { line in
                    Rectangle().fill(.primary.opacity(0.5)).frame(width: 1.5).offset(x: x(line, width: proxy.size.width))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// 단어 칩을 줄바꿈하며 늘어놓는다.
private struct WordChipFlow: View {
    let words: [FitWordCount]
    let tint: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(words) { word in
                HStack(spacing: 3) {
                    Text(word.word)
                    if word.count > 1 {
                        Text("×\(word.count)").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.1), in: Capsule())
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [], y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#Preview("상세") {
    BookFitDetailView(report: .preview, onClassifyTopics: {})
}
