import SwiftUI

private struct ActiveSpotlightTargetKey: EnvironmentKey {
    static let defaultValue: SpotlightTarget? = nil
}

extension EnvironmentValues {
    var activeSpotlightTarget: SpotlightTarget? {
        get { self[ActiveSpotlightTargetKey.self] }
        set { self[ActiveSpotlightTargetKey.self] = newValue }
    }
}

struct ComponentSpotlightModifier: ViewModifier {
    @Environment(\.activeSpotlightTarget) private var activeTarget
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let target: SpotlightTarget

    private var isDimmed: Bool {
        guard let activeTarget else { return false }
        return activeTarget != target
    }

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.32 : 1)
            .brightness(isDimmed ? -0.24 : 0)
            .saturation(isDimmed ? 0.24 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.22),
                value: isDimmed
            )
            .accessibilityHidden(activeTarget != nil && isDimmed)
    }
}

extension View {
    /// 컴포넌트 자체를 밝히거나 낮춥니다. 프레임 측정이나 마스크를 만들지 않습니다.
    func componentSpotlight(_ target: SpotlightTarget) -> some View {
        modifier(ComponentSpotlightModifier(target: target))
    }
}
