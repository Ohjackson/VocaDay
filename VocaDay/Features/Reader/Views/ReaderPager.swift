import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 페이지 나누기 기준. 화면(창) 하나가 페이지 하나다.
struct ReaderPagerLayout: Equatable {
    var size: CGSize
    var safeTop: CGFloat = 0
    var safeBottom: CGFloat = 0
    /// 좌우 최소 여백.
    var minMarginX: CGFloat = 24
    /// 본문 열을 약 70자로 줄일지 (Mac).
    var limitsBodyWidth = false

    func metrics(fontSize: Double, lineHeight: Double) -> ReaderPageMetrics {
        ReaderPageMetrics.screen(
            size: size,
            safeTop: safeTop,
            safeBottom: safeBottom,
            minMarginX: minMarginX,
            maxBodyWidth: limitsBodyWidth ? ReaderPageMetrics.readableBodyWidth(fontSize: CGFloat(fontSize)) : nil,
            fontSize: CGFloat(fontSize),
            lineHeight: CGFloat(lineHeight)
        )
    }
}

/// 마일드 화면 본문: 화면 크기 페이지를 좌우로 넘긴다. iPhone·Mac이 같이 쓴다.
/// 글자 크기·줄 간격·화면 크기가 바뀌면 다시 나누고, 읽던 문장이 있는 페이지로 돌아간다.
struct ReaderPager: View {
    let session: ReaderSession
    let appearance: ReaderAppearance
    let layout: ReaderPagerLayout
    /// 단어가 아닌 곳을 눌렀을 때.
    var onBackgroundTap: () -> Void = {}

    @State private var pages: [ReaderPage] = []
    @State private var layoutMetrics: ReaderPageMetrics?
    @State private var texts = ReaderPageTextCache()
    @State private var currentPage: Int?
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    var body: some View {
        let metrics = layout.metrics(fontSize: appearance.fontSize, lineHeight: appearance.lineHeight)
        ScrollView(.horizontal) {
            if let layoutMetrics {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { page in
                        ReaderPageView(
                            session: session,
                            page: page,
                            text: texts.text(for: page, book: session.book, metrics: layoutMetrics, theme: appearance.theme),
                            appearance: appearance,
                            onBackgroundTap: onBackgroundTap
                        )
                    }
                }
                .scrollTargetLayout()
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(session.isDraggingSelection)
        .scrollPosition(id: $currentPage)
        .scrollIndicators(.hidden)
        .background(appearance.page)
        .overlay {
            if pages.isEmpty { ProgressView() }
        }
        .background { pageKeys }
        #if os(macOS)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        #endif
        .onChange(of: currentPage) { _, index in
            guard let index, pages.indices.contains(index) else { return }
            session.noteVisiblePages([pages[index].positions])
        }
        .onChange(of: session.scrollRequest) { _, request in
            show(request.position, animated: true)
        }
        .task(id: metrics) {
            // 창 크기를 끄는 동안 매번 나누지 않게 잠깐 기다린다. 처음 열 때는 바로 나눈다.
            if !pages.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }
            let book = session.book
            let result = await Task.detached(priority: .userInitiated) {
                ReaderPaginator.paginate(book: book, metrics: metrics)
            }.value
            if Task.isCancelled { return }
            pages = result
            layoutMetrics = metrics
            // 다시 나눈 뒤에도 읽던 문장이 있는 페이지를 연다.
            try? await Task.sleep(for: .milliseconds(30))
            show(session.position, animated: false)
        }
    }

    private func pageIndex(of position: ReadingPosition) -> Int? {
        pages.firstIndex { $0.positions.contains(position) }
    }

    private func show(_ position: ReadingPosition, animated: Bool) {
        guard let index = pageIndex(of: position), index != currentPage else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { currentPage = index }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { currentPage = index }
        }
    }

    private func turn(by delta: Int) {
        let target = (currentPage ?? 0) + delta
        guard pages.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { currentPage = target }
    }

    /// ←/→, Page Up/Down 으로 페이지 넘기기 (Mac, iPad 키보드).
    private var pageKeys: some View {
        ZStack {
            Button("이전 페이지") { turn(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("다음 페이지") { turn(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("이전 페이지") { turn(by: -1) }
                .keyboardShortcut(.pageUp, modifiers: [])
            Button("다음 페이지") { turn(by: 1) }
                .keyboardShortcut(.pageDown, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    #if os(macOS)
    /// Mac: 가로 스크롤 뷰가 ←/→ 를 먼저 가져가서 단축키 버튼까지 오지 않는다.
    /// 창으로 들어오는 키를 먼저 보고 페이지를 넘긴다. 글 입력 중(첫 응답자가 글 상자)이면 건드리지 않는다.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty, !(event.window?.firstResponder is NSText) else { return event }
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated { () -> Bool in
                switch keyCode {
                case 123, 116: turn(by: -1); return true // ←, Page Up
                case 124, 121: turn(by: 1); return true // →, Page Down
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
    #endif
}

final class ReaderPageTextCache {
    private struct Key: Equatable {
        var bookID: String
        var metrics: ReaderPageMetrics
        var theme: ReaderTheme
    }

    private var key: Key?
    private var texts: [Int: ReaderPageText] = [:]

    func text(for page: ReaderPage, book: BookDocument, metrics: ReaderPageMetrics, theme: ReaderTheme) -> ReaderPageText {
        let newKey = Key(bookID: book.id, metrics: metrics, theme: theme)
        if newKey != key {
            key = newKey
            texts = [:]
        }
        if let cached = texts[page.index], cached.page == page { return cached }
        let text = ReaderPageText(book: book, page: page, metrics: metrics, palette: theme.palette)
        texts[page.index] = text
        return text
    }
}

/// 페이지 한 장: 화면 전체가 페이지 색이고 글과 왼쪽 위 쪽 번호만 있다.
struct ReaderPageView: View {
    let session: ReaderSession
    let page: ReaderPage
    let text: ReaderPageText
    let appearance: ReaderAppearance
    var onBackgroundTap: () -> Void = {}

    private var metrics: ReaderPageMetrics { text.metrics }

    private var state: ReaderPageDrawState {
        let positions = Set(page.positions)
        let speaking = session.speakingPosition
        let active = session.activeWord?.ref
        let onPage = active.flatMap { positions.contains($0.position) ? $0 : nil }
        return ReaderPageDrawState(
            // 재생하지 않을 때는 읽는 문장을 표시하지 않는다.
            highlight: speaking.flatMap { positions.contains($0) ? $0 : nil },
            bookmarks: Set(session.bookmarks.map(\.position)).intersection(positions),
            activeWord: onPage,
            activeWordEnd: onPage == nil ? nil : session.activeWord?.endIndex,
            phraseDraft: session.phraseDraft.flatMap { positions.contains($0.position) ? $0 : nil }
        )
    }

    var body: some View {
        let state = state
        ZStack(alignment: .topLeading) {
            appearance.page
            ReaderPageCanvas(session: session, text: text, state: state, onBackgroundTap: onBackgroundTap)
            Text("\(page.index + 1)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(appearance.secondary)
                .padding(.leading, metrics.marginX)
                .padding(.top, metrics.pageNumberTop)
                .allowsHitTesting(false)
                .accessibilityLabel("\(page.index + 1)쪽")
        }
        .frame(width: metrics.pageWidth, height: metrics.pageHeight)
        .overlay(alignment: .topLeading) {
            // 단어 자리에 보이지 않는 칸을 두고 거기에 팝오버를 붙인다.
            // `attachmentAnchor: .rect(...)`는 macOS에서 세로 위치가 어긋나 다른 줄을 가리켰다.
            let anchor = popoverAnchor(state.activeWord)
            Color.clear
                .frame(width: max(anchor.width, 1), height: max(anchor.height, 1))
                // 위쪽 절반의 단어는 아래로, 아래쪽 절반은 위로 띄운다. 위에 자리가 없으면 상자가 눌려 잘린다.
                .popover(
                    isPresented: popoverBinding(state.activeWord),
                    arrowEdge: anchor.midY < metrics.pageHeight / 2 ? .top : .bottom
                ) {
                    ReaderWordPopover(session: session, appearance: appearance)
                }
                .padding(.leading, anchor.minX)
                .padding(.top, anchor.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func popoverBinding(_ active: ReaderTokenRef?) -> Binding<Bool> {
        Binding(
            get: { active != nil },
            set: { isPresented in
                if !isPresented, let active, session.activeWord?.ref == active {
                    session.activeWord = nil
                }
            }
        )
    }

    private func popoverAnchor(_ active: ReaderTokenRef?) -> CGRect {
        active.flatMap { text.wordRect($0) } ?? CGRect(x: metrics.pageWidth / 2, y: metrics.marginTop, width: 1, height: 1)
    }
}

/// 단어를 누르면 그 단어 옆에 뜨는 뜻 상자. 내용은 `WordLookupCard` 가 그린다.
/// iPhone도 시트가 아니라 팝오버로 띄운다.
struct ReaderWordPopover: View {
    let session: ReaderSession
    let appearance: ReaderAppearance

    /// 흰 상자, 밤 테마는 어두운 회색.
    private var background: Color {
        appearance.theme == .night ? Color(readerHex: 0x33302C) : .white
    }

    var body: some View {
        Group {
            if let active = session.activeWord {
                WordLookupCard(context: active.context, book: session.book)
                    .frame(width: 300, alignment: .leading)
            }
        }
        .environment(\.colorScheme, appearance.theme.colorScheme)
        .tint(appearance.accent)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(background)
    }
}

struct ReaderTranslationStrip: View {
    let session: ReaderSession
    let appearance: ReaderAppearance

    var body: some View {
        if let position = session.translationPosition, let sentence = session.book.sentence(at: position),
           let translation = sentence.translation {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color(readerHex: appearance.palette.word))
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sentence.text)
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(appearance.secondary)
                        .lineLimit(2)
                    Text(translation)
                        .font(.callout)
                        .foregroundStyle(appearance.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    session.hideTranslation()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appearance.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("번역 닫기")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(appearance.page)
            .overlay { Rectangle().strokeBorder(appearance.border, lineWidth: 1) }
        }
    }
}

/// 길게 누를 때 뜨는 문장 미리보기 (번역 포함).
struct ReaderSentencePreview: View {
    let sentence: BookSentence?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sentence?.text ?? "")
                .font(.system(.body, design: .serif))
            if let translation = sentence?.translation {
                Text(translation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

enum ReaderPasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
