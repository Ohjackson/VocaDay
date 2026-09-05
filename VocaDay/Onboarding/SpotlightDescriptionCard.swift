import SwiftUI

struct SpotlightDescriptionCard: View {
    let step: SpotlightStep
    let canGoBack: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("처음 사용 안내")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: 8)

                Text("\(step.rawValue + 1)/\(SpotlightStep.allCases.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(SpotlightStep.allCases.count)단계 중 \(step.rawValue + 1)단계")
            }

            Text(step.title)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(step.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
    }

    @ViewBuilder
    private var backButton: some View {
        if canGoBack {
            Button("이전", action: onBack)
                .buttonStyle(.bordered)
        }
    }

    private var nextButton: some View {
        Button(step == SpotlightStep.allCases.last ? "완료" : "다음", action: onNext)
            .buttonStyle(.borderedProminent)
    }
}
