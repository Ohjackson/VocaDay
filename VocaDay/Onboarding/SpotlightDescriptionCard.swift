import SwiftUI

struct SpotlightDescriptionCard: View {
    let step: SpotlightStep
    let stepNumber: Int
    let stepCount: Int
    let canGoBack: Bool
    var finishTitle = "시작하기"
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("빠른 시작")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: 8)

                Text("\(stepNumber)/\(stepCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(stepCount)단계 중 \(stepNumber)단계")
            }

            Text(step.title)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            // ScrollView 로 감싸면 iOS 26 재질 카드 안에서 본문이 그려지지 않는 경우가 있어 글자 높이만큼 그대로 둔다.
            messageText

            #if os(macOS)
            horizontalControls
            #else
            ViewThatFits(in: .horizontal) {
                horizontalControls
                compactControls
            }
            #endif
        }
        .padding(18)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var messageText: some View {
        Text(step.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalControls: some View {
        HStack(spacing: 10) {
            skipButton
            Spacer(minLength: 8)
            backButton
            nextButton
        }
    }

    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            skipButton

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                backButton
                nextButton
            }
        }
    }

    private var skipButton: some View {
        Button("건너뛰기", action: onSkip)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var backButton: some View {
        if canGoBack {
            Button("이전", action: onBack)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
    }

    private var nextButton: some View {
        Button(stepNumber == stepCount ? finishTitle : "다음", action: onNext)
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
    }
}
