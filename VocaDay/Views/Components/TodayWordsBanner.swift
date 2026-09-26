import SwiftUI

/// 데이 목록 위 '오늘의 새 단어' 진입점. 실제 데이 화면과 온보딩 목업이 같은 모양을 쓴다.
/// 오늘 이미 만들었으면 비활성으로 남겨 내일 다시 열린다는 걸 보여 준다.
struct TodayWordsBanner: View {
    let addedToday: Bool
    let onStart: () -> Void
    let onOpenSetAside: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStart) {
                HStack(spacing: 10) {
                    Image(systemName: addedToday ? "checkmark.circle" : "sparkles")
                        .foregroundStyle(addedToday ? Color.secondary : Color.accentColor)
                    Text(addedToday ? "오늘 단어장 완료 · 내일 다시" : "오늘의 새 단어 \(BundledWordPack.dailyCount)개 고르기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(addedToday ? Color.secondary : Color.primary)
                    Spacer(minLength: 0)
                    if !addedToday {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(addedToday)

            Divider()
                .frame(height: 18)

            Button(action: onOpenSetAside) {
                Image(systemName: "archivebox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("보관한 단어")
            .help("보관한 단어")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            (addedToday ? Color.secondary : Color.accentColor).opacity(0.08),
            in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        )
        .componentSpotlight(.todayWordsBanner)
    }
}
