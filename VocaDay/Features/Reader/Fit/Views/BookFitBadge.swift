import SwiftUI

/// 책 목록 카드에 붙이는 적합도 줄.
///
/// ```
/// [정독용] 아는 단어 96.4%
/// 토익 단어 41종 (1,000단어당 18회) · 복습 단어 12개 재등장 · 토익 상황 85%
/// ⚠️ 번역 누락 0 · 문장 오류 2
/// ```
/// `.compact` 는 첫 줄만 보인다.
struct BookFitBadge: View {
    enum Style {
        case compact
        case full
    }

    let report: BookFitReport
    var style: Style = .full

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                BookFitVerdictPill(verdict: report.verdict)
                Text("아는 단어 \(BookFitFormat.percent(report.overall.coverage))")
                    .font(.subheadline.weight(.medium).monospacedDigit())
            }
            if style == .full {
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if hasWarnings {
                    Label(warningLine, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var parts = [
            "토익 단어 \(report.overall.examTypeCount)종 (1,000단어당 \(BookFitFormat.perThousand(report.overall.examPerThousand))회)",
        ]
        if !report.reviewWords.isEmpty {
            parts.append("복습 단어 \(report.reviewWords.count)개 재등장")
        }
        if let topics = report.topics {
            parts.append("토익 상황 \(BookFitFormat.percent(topics.examSituationShare, digits: 0))")
        }
        return parts.joined(separator: " · ")
    }

    private var hasWarnings: Bool {
        report.warningCount(.missingTranslation) + report.sentenceProblemCount + report.glossaryProblemCount > 0
    }

    private var warningLine: String {
        var parts = [
            "번역 누락 \(report.warningCount(.missingTranslation))",
            "문장 오류 \(report.sentenceProblemCount)",
        ]
        if report.glossaryProblemCount > 0 {
            parts.append("사전 위치 \(report.glossaryProblemCount)")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("배지") {
    VStack(alignment: .leading, spacing: 20) {
        BookFitBadge(report: .preview)
        BookFitBadge(report: .preview, style: .compact)
    }
    .padding()
}
