#if os(iOS)
import SwiftUI

/// iPhone 단어·문장 카드를 페이지 위에 직접 띄우는 상자.
/// 시스템 팝오버는 바깥을 누른 첫 터치를 닫는 데 써 버려서 다른 단어를 두 번 눌러야 했다. 이 상자는 본문 터치를 막지 않는다.
struct ReaderFloatingCard<Content: View>: View {
    /// 가리킬 글자 영역 (페이지 기준).
    let anchor: CGRect
    let metrics: ReaderPageMetrics
    let appearance: ReaderAppearance
    let width: CGFloat
    let onClose: () -> Void
    @ViewBuilder let content: Content

    private let gap: CGFloat = 4
    private let sideMargin: CGFloat = 10

    /// 위쪽 절반의 글자는 아래로, 아래쪽 절반은 위로 띄운다.
    private var opensBelow: Bool { anchor.midY < metrics.pageHeight / 2 }
    private var leading: CGFloat {
        min(max(anchor.midX - width / 2, sideMargin), max(sideMargin, metrics.pageWidth - sideMargin - width))
    }
    private var top: CGFloat { opensBelow ? anchor.maxY + gap : metrics.pageNumberTop }
    private var bottom: CGFloat { opensBelow ? metrics.pageHeight - metrics.marginBottom + 16 : anchor.minY - gap }

    var body: some View {
        content
            .frame(width: width, alignment: .leading)
            .padding(opensBelow ? .top : .bottom, ReaderCardBubble.arrowHeight)
            .background {
                ReaderCardBubble(arrowX: anchor.midX - leading, pointsUp: opensBelow)
                    .fill(appearance.theme == .night ? Color(readerHex: 0x33302C) : .white)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
            }
            .contentShape(ReaderCardBubble(arrowX: anchor.midX - leading, pointsUp: opensBelow))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onClose)
            // 자리보다 길면 카드 안에서 스크롤된다. 남는 빈 곳은 터치를 막지 않는다.
            .frame(height: max(bottom - top, 0), alignment: opensBelow ? .top : .bottom)
            .padding(.leading, leading)
            .padding(.top, top)
            .environment(\.colorScheme, appearance.theme.colorScheme)
            .tint(appearance.accent)
    }
}

/// 둥근 상자 + 글자를 가리키는 화살표.
struct ReaderCardBubble: Shape {
    static let arrowHeight: CGFloat = 10
    var arrowX: CGFloat
    var pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 26
        let half: CGFloat = 11
        var box = rect
        box.size.height = max(rect.height - Self.arrowHeight, 0)
        if pointsUp { box.origin.y += Self.arrowHeight }
        let x = min(max(rect.minX + arrowX, box.minX + radius + half), box.maxX - radius - half)
        let base = pointsUp ? box.minY : box.maxY
        let tip = pointsUp ? rect.minY : rect.maxY
        var arrow = Path()
        arrow.move(to: CGPoint(x: x - half, y: base))
        arrow.addLine(to: CGPoint(x: x, y: tip))
        arrow.addLine(to: CGPoint(x: x + half, y: base))
        arrow.closeSubpath()
        return Path(roundedRect: box, cornerRadius: radius, style: .continuous).union(arrow)
    }
}
#endif
