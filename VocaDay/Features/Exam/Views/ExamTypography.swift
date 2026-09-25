import SwiftUI

/// 시험 화면 글씨 배율. 창(화면)이 넓어지면 글씨도 함께 커진다.
extension EnvironmentValues {
    @Entry var examTextScale: CGFloat = 1
}

enum ExamTypography {
    /// 폭 560pt(휴대폰)까지는 1배, 넓어질수록 최대 1.6배.
    static func scale(forWidth width: CGFloat) -> CGFloat {
        min(max(width / 560, 1), 1.6)
    }

    /// 플랫폼 기본 글꼴 크기 (pt).
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote: 10
        case .caption, .caption2: 10
        @unknown default: 13
        }
        #else
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
        #endif
    }

    /// 사용자가 고른 글자 크기(다이내믹 타입)도 함께 반영한다.
    static func dynamicFactor(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.2
        case .accessibility4: 2.5
        case .accessibility5: 2.8
        @unknown default: 1
        }
    }
}

private struct ExamFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.examTextScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let size = ExamTypography.baseSize(style) * scale * ExamTypography.dynamicFactor(dynamicTypeSize)
        let defaultWeight: Font.Weight = style == .headline ? .semibold : .regular
        content.font(.system(size: size, weight: weight ?? defaultWeight))
    }
}

extension View {
    /// 시험 화면용 글꼴: 텍스트 스타일 크기 × 화면 배율 × 다이내믹 타입.
    func examFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ExamFontModifier(style: style, weight: weight))
    }
}

/// 예문의 한국어 해석. 기본은 가려 두고, 눌러서 볼 수 있다.
/// 스스로 연 경우에는 `onReveal`이 불려 그 문제가 세션 끝에 한 번 더 나온다.
struct ExampleTranslationToggle: View {
    let translation: String
    /// 설정에서 "처음부터 보기"를 켠 경우. 이때는 힌트로 치지 않는다.
    let showsByDefault: Bool
    /// 답을 낸 뒤에는 버튼을 숨긴다.
    var isLocked = false
    let onReveal: () -> Void

    @State private var isRevealed = false

    var body: some View {
        if !translation.isEmpty {
            if showsByDefault || isRevealed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translation)
                        .examFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isRevealed, !showsByDefault {
                        Label("해석을 본 문제는 끝나고 한 번 더 풀어요", systemImage: "arrow.counterclockwise")
                            .examFont(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .transition(.opacity)
            } else if !isLocked {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isRevealed = true }
                    onReveal()
                } label: {
                    Label("해석 보기", systemImage: "eye")
                        .examFont(.subheadline, weight: .medium)
                }
                .buttonStyle(.borderless)
                .help("예문의 한국어 해석을 봅니다. 본 문제는 끝나고 한 번 더 나와요.")
            }
        }
    }
}
