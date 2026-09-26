import SwiftUI

/// 단어 데이터 점검 결과. 편집 화면과 저장 전 목록에서 쓴다.
struct WordDataCheckView: View {
    let issues: [WordDataCheck.Issue]
    var compact = false

    var body: some View {
        if WordDataCheck.isQuizReady(issues) && (compact || issues.isEmpty) {
            Label("복습·시험 4가지 유형 준비됨", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else if compact, let first = issues.first(where: { $0 != .missingExampleTranslation }) {
            Label(first.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(first.isBlocking ? .red : .orange)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.self) { issue in
                    Label(issue.message, systemImage: issue == .missingExampleTranslation ? "info.circle" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(issue.isBlocking ? .red : (issue == .missingExampleTranslation ? .secondary : .orange))
                }
                if issues.contains(.exampleMissingWord) || issues.contains(.missingExample) {
                    Text("예: postpone → “They postponed the meeting.” 처럼 단어(활용형 가능)가 들어간 한 문장을 적어 주세요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if issues.contains(.someExampleLinesMissingWord) || issues.contains(.exampleTranslationLineMismatch) {
                    Text("품사가 여럿이면 “1. The record is clear.↵2. She recorded it.” 처럼 줄마다 단어를 넣고, 번역도 같은 번호로 적어 주세요.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
