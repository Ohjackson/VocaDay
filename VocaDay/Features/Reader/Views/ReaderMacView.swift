#if os(macOS)
import SwiftUI

/// Mac 책 화면 (마일드): iPhone과 같은 화면. 가운데 본문 열(약 70자), 페이지는 좌우로 넘긴다
/// (트랙패드 쓸기, Page Up/Down). 오른쪽 위 버튼이나 위·아래 가장자리에 마우스를 올리면 막대가 나온다.
/// 스페이스는 재생·정지, ←/→ 는 이전·다음 문장, ⌘D 는 북마크. 목차 패널은 「⋯」 메뉴에서 연다.
struct ReaderMacView: View {
    let session: ReaderSession
    let settings: ReaderSettingsBindings

    @Environment(\.dismiss) private var dismiss
    @State private var showsChrome = false
    @State private var showsPanel = false
    @State private var showsAppearance = false
    @State private var panelTab = ReaderContentsPanel.Tab.contents

    private var appearance: ReaderAppearance { settings.appearance }

    var body: some View {
        GeometryReader { proxy in
            let layout = ReaderPagerLayout(size: proxy.size, minMarginX: 48, limitsBodyWidth: true)
            ZStack(alignment: .topTrailing) {
                ReaderPager(session: session, appearance: appearance, layout: layout, onBackgroundTap: hideChrome)

                VStack(spacing: 0) {
                    if showsChrome {
                        ReaderTopBar(
                            session: session,
                            appearance: appearance,
                            settings: settings,
                            actions: menuActions,
                            showsAppearance: $showsAppearance,
                            onBack: { dismiss() }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        edgeHoverStrip
                    }
                    Spacer(minLength: 0)
                    ReaderTranslationStrip(session: session, appearance: appearance)
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    if showsChrome {
                        ReaderBottomBar(session: session, appearance: appearance)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        edgeHoverStrip
                    }
                }

                ReaderChromeToggle(isShown: $showsChrome, appearance: appearance)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                    .help(showsChrome ? "메뉴 숨기기" : "메뉴 보기")
            }
        }
        .background { ReaderKeyboardShortcuts(session: session) }
        .modifier(ReaderSpeechSettingsSync(session: session, settings: settings))
        .environment(\.colorScheme, appearance.theme.colorScheme)
        .tint(appearance.accent)
        // 제목·뒤로는 위 막대가 맡는다. 창 도구 막대에는 사이드바 단추만 남긴다.
        .navigationTitle(session.book.title)
        .navigationSubtitle(session.currentChapterTitle)
        .toolbar(removing: .title)
        .navigationBarBackButtonHidden(true)
        .inspector(isPresented: $showsPanel) {
            ReaderContentsPanel(session: session, tab: $panelTab)
                .inspectorColumnWidth(min: 220, ideal: 270, max: 360)
        }
    }

    private var menuActions: ReaderMenuActions {
        ReaderMenuActions(
            showContents: { showsPanel = true },
            showAppearance: { showsAppearance = true }
        )
    }

    /// 막대가 숨어 있을 때 위·아래 가장자리. 마우스를 올리면 막대를 보인다.
    private var edgeHoverStrip: some View {
        Color.clear
            .frame(height: 10)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside, !showsChrome else { return }
                withAnimation(.easeOut(duration: 0.2)) { showsChrome = true }
            }
    }

    private func hideChrome() {
        guard showsChrome else { return }
        withAnimation(.easeOut(duration: 0.2)) { showsChrome = false }
    }
}
#endif
