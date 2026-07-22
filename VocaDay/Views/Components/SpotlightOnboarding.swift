import SwiftUI

enum OnboardingSpotlightTarget: Hashable {
    case days
    case addMode
    case addInput
    case jsonInput
    case addActions
    case review
    case study
}

struct OnboardingSpotlightPreferenceKey: PreferenceKey {
    static var defaultValue: [OnboardingSpotlightTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [OnboardingSpotlightTarget: Anchor<CGRect>],
        nextValue: () -> [OnboardingSpotlightTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingSpotlight(_ target: OnboardingSpotlightTarget) -> some View {
        anchorPreference(key: OnboardingSpotlightPreferenceKey.self, value: .bounds) { anchor in
            [target: anchor]
        }
    }
}

struct SpotlightOnboardingOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let step: Int
    let totalSteps: Int
    let spotlightRect: CGRect?
    let canGoBack: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let expandedRect = spotlightRect?.insetBy(dx: -10, dy: -10)
            let showCardAbove = expandedRect.map { $0.midY > proxy.size.height * 0.58 } ?? false

            ZStack {
                Color.black.opacity(0.66)
                    .ignoresSafeArea()

                if let expandedRect {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black)
                        .frame(width: expandedRect.width, height: expandedRect.height)
                        .position(x: expandedRect.midX, y: expandedRect.midY)
                        .blendMode(.destinationOut)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: expandedRect.width, height: expandedRect.height)
                        .position(x: expandedRect.midX, y: expandedRect.midY)
                        .shadow(color: Color.white.opacity(0.35), radius: 12)
                }

                VStack(spacing: 0) {
                    if showCardAbove {
                        onboardingCard
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        onboardingCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .compositingGroup()
        }
        .accessibilityAddTraits(.isModal)
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("VocaDay 시작 안내")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Text("\(step)/\(totalSteps)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.title3.weight(.bold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("건너뛰기", action: onSkip)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

                Spacer()

                if canGoBack {
                    Button("이전", action: onBack)
                        .buttonStyle(.bordered)
                }

                Button(step == totalSteps ? "시작하기" : "다음", action: onNext)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(maxWidth: 440, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
}
