import SwiftUI

/// 학습 방식 안내. 사용자가 "매일 오늘 복습만 하면 된다"는 것을 믿고 맡길 수 있도록 근거를 짧게 설명한다.
struct LearningMethodCard: View {
    @AppStorage("isLearningMethodCardExpanded") private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("매일 ‘오늘 복습’만 끝내면 돼요")
                            .font(.subheadline.weight(.semibold))
                        Text("복습 카드와 시험 중 무엇으로 풀어도 같은 일정에 반영돼요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "학습 방식 설명을 접습니다." : "학습 방식 설명을 펼칩니다.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    point(
                        "calendar.badge.clock",
                        "간격 반복",
                        "맞힐 때마다 다음 복습까지 간격이 1 → 2 → 4 → 7 → 13 → 30학습일처럼 늘어나요. 잊을 즈음에 다시 보여 주는 방식은 망각 곡선 연구 이후 여러 실험에서 효과가 확인된 방법이에요."
                    )
                    point(
                        "lightbulb",
                        "먼저 떠올리기",
                        "뜻을 보기 전에 스스로 떠올리게 해요. 다시 읽기보다 떠올려 보는 연습(인출 연습)이 기억에 더 오래 남는다는 연구가 많아요."
                    )
                    point(
                        "square.grid.2x2",
                        "문제 유형 섞기",
                        "짝 맞추기·뜻 고르기·빈칸 고르기로 시작해요. 익숙한 단어일수록 글자 조각·빈칸 쓰기·한→영 쓰기·듣고 쓰기처럼 직접 떠올리는 문제가 많아져 조금 더 어렵게, 더 단단하게 외워요."
                    )
                    point(
                        "arrow.counterclockwise",
                        "틀리면 곧바로 다시",
                        "틀린 단어는 단계가 내려가고 \(SRSEngine.retryDelayHours)시간 뒤 재도전에서 한 번 더 나와요. 미리 복습하다 ‘다시’를 고른 단어도 오늘 목록에 들어가요."
                    )
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .calmCard()
    }

    private func point(_ systemImage: String, _ title: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
