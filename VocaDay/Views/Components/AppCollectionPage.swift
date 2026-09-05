import SwiftUI

/// 목록 중심 화면에서 사용하는 실제 프로덕션 스크롤 레이아웃입니다.
/// 온보딩도 이 컨테이너를 사용해 콘텐츠 폭과 여백을 실제 화면과 동일하게 유지합니다.
struct AppCollectionPage<Content: View>: View {
    let maxContentWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    private let content: () -> Content

    init(
        maxContentWidth: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxContentWidth = maxContentWidth
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: maxContentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
