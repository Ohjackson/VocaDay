#if os(iOS)
import SwiftUI

/// iPhone 책 화면 (마일드): 화면 전체가 페이지 색이고 글만 있다. 페이지는 좌우로 넘긴다.
/// 평소에는 오른쪽 위 버튼 하나만 보이고, 누르면 위·아래 막대가 나온다. 단어 뜻은 단어 옆 팝오버.
struct ReaderPhoneView: View {
    @Bindable var session: ReaderSession
    let settings: ReaderSettingsBindings

    @Environment(\.dismiss) private var dismiss
    @State private var showsChrome = false
    @State private var showsContents = false
    @State private var showsAppearance = false
    @State private var contentsTab = ReaderContentsPanel.Tab.contents

    private var appearance: ReaderAppearance { settings.appearance }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let layout = ReaderPagerLayout(
                size: CGSize(
                    width: proxy.size.width + insets.leading + insets.trailing,
                    height: proxy.size.height + insets.top + insets.bottom
                ),
                safeTop: insets.top,
                safeBottom: insets.bottom,
                minMarginX: 24
            )
            ZStack(alignment: .topTrailing) {
                ReaderPager(session: session, appearance: appearance, layout: layout, onBackgroundTap: hideChrome)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if showsChrome {
                        ReaderTopBar(
                            session: session,
                            appearance: appearance,
                            settings: settings,
                            safeTop: insets.top,
                            actions: menuActions,
                            showsAppearance: $showsAppearance,
                            onBack: { dismiss() }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    ReaderTranslationStrip(session: session, appearance: appearance)
                        .padding(.horizontal, 16)
                        .padding(.bottom, showsChrome ? 10 : max(insets.bottom, 12))
                    if showsChrome {
                        ReaderBottomBar(session: session, appearance: appearance, safeBottom: insets.bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea()

                ReaderChromeToggle(isShown: $showsChrome, appearance: appearance)
                    .padding(.trailing, 8 + insets.trailing)
                    .padding(.top, insets.top - 4)
                    .ignoresSafeArea()
            }
        }
        .modifier(ReaderSpeechSettingsSync(session: session, settings: settings))
        .environment(\.colorScheme, appearance.theme.colorScheme)
        .tint(appearance.accent)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showsContents) {
            ReaderContentsPanel(session: session, tab: $contentsTab) {
                showsContents = false
            }
            .padding(.top, 8)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(\.colorScheme, appearance.theme.colorScheme)
            .tint(appearance.accent)
        }
    }

    private var menuActions: ReaderMenuActions {
        ReaderMenuActions(
            showContents: { showsContents = true },
            showAppearance: { showsAppearance = true }
        )
    }

    private func hideChrome() {
        guard showsChrome else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsChrome = false }
    }
}
#endif
