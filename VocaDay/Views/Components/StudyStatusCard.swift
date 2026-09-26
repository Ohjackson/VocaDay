import SwiftUI

/// 학습 탭 맨 위의 '오늘 학습' 카드. 실제 학습 화면과 온보딩 목업이 같은 모양을 쓴다.
struct StudyStatusCard: View {
    let headline: String
    let subheadline: String
    let learningDayNumber: Int
    /// 오늘 대상이 있을 때만 (완료 수, 전체 수).
    let progress: (graded: Int, total: Int)?
    let buttonTitle: String
    let isButtonEnabled: Bool
    var footnote: String?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.title3.weight(.semibold))
                    Text(subheadline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("학습일 \(learningDayNumber)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            if let progress {
                ProgressView(value: Double(progress.graded), total: Double(progress.total)) {
                    Text("오늘 \(progress.graded)/\(progress.total)개 완료 · 카드와 시험 합산")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.green)
            }

            Button(action: onStart) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isButtonEnabled)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.cardPadding)
        .calmCard()
        .componentSpotlight(.studyStatus)
    }
}
