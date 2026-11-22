import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 페이지 본문에 그릴 상태. 바뀔 때만 다시 그린다.
nonisolated struct ReaderPageDrawState: Equatable {
    /// 평면으로 칠할 읽는 문장.
    var highlight: ReadingPosition?
    /// 이 페이지에 있는 북마크 문장.
    var bookmarks: Set<ReadingPosition> = []
    /// 카드가 열린 단어.
    var activeWord: ReaderTokenRef?
}

/// 페이지 한 장의 조판 결과. 그리기·누른 곳 찾기·단어 위치 계산을 한곳에서 한다. 좌표는 페이지 기준.
final class ReaderPageText {
    let page: ReaderPage
    let metrics: ReaderPageMetrics
    let palette: ReaderPalette

    private let stack: ReaderTextStack
    private let spans: [ReaderSentenceSpan]
    private let bodyFont: ReaderPlatformFont
    private let book: BookDocument
    private var tokenCache: [ReadingPosition: [ReaderTokenizer.Token]] = [:]

    init(book: BookDocument, page: ReaderPage, metrics: ReaderPageMetrics, palette: ReaderPalette) {
        self.book = book
        self.page = page
        self.metrics = metrics
        self.palette = palette
        let composer = ReaderPageComposer(
            book: book,
            fontSize: metrics.fontSize,
            lineHeight: metrics.lineHeight,
            textColor: ReaderPlatformColor(readerHex: palette.text),
            secondaryColor: ReaderPlatformColor(readerHex: palette.secondary)
        )
        bodyFont = composer.bodyFont
        let (text, spans) = composer.compose(page.blocks)
        self.spans = spans
        stack = ReaderTextStack(width: metrics.bodyWidth)
        stack.storage.setAttributedString(text)
    }

    private var origin: CGPoint { metrics.bodyOrigin }

    /// 접근성용 페이지 글.
    var plainText: String { stack.storage.string }

    func tokens(at position: ReadingPosition) -> [ReaderTokenizer.Token] {
        if let cached = tokenCache[position] { return cached }
        let tokens = ReaderTokenizer.tokens(in: book.sentence(at: position)?.text ?? "")
        tokenCache[position] = tokens
        return tokens
    }

    // MARK: 누른 곳 찾기

    struct Hit: Equatable {
        var position: ReadingPosition
        /// 누른 단어. 단어 사이·문장부호만 있는 조각이면 nil.
        var token: Int?
    }

    func hit(at point: CGPoint) -> Hit? {
        let layout = stack.layoutManager
        guard layout.numberOfGlyphs > 0 else { return nil }
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        layout.ensureLayout(for: stack.container)
        let used = layout.usedRect(for: stack.container)
        guard local.y >= -4, local.y <= used.maxY + 4, local.x >= -8, local.x <= metrics.bodyWidth + 8 else { return nil }

        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: local, in: stack.container, fractionOfDistanceThroughGlyph: &fraction)
        let character = layout.characterIndexForGlyph(at: glyph)
        let glyphRect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: stack.container)
        let onGlyph = local.x >= glyphRect.minX - 6 && local.x <= glyphRect.maxX + 6

        // 문장 사이 띄어쓰기는 어느 문장에도 없다. 그때는 앞 문장으로 본다.
        guard let span = spans.first(where: { NSLocationInRange(character, $0.range) })
            ?? spans.last(where: { $0.range.location <= character })
        else { return nil }
        let offset = character - span.range.location
        let token = onGlyph ? tokens(at: span.position).firstIndex { $0.range.contains(offset) && $0.surface != nil } : nil
        return Hit(position: span.position, token: token)
    }

    // MARK: 위치 계산

    private struct LineSegment {
        var rect: CGRect
        var baseline: CGFloat
    }

    /// 글자 범위가 걸친 줄마다 가로 범위와 기준선 (페이지 기준).
    private func segments(for range: NSRange) -> [LineSegment] {
        let layout = stack.layoutManager
        layout.ensureLayout(for: stack.container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return [] }
        var result: [LineSegment] = []
        layout.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, container, lineGlyphs, _ in
            let part = NSIntersectionRange(lineGlyphs, glyphs)
            guard part.length > 0 else { return }
            var bounds = layout.boundingRect(forGlyphRange: part, in: container)
            // 줄 끝 띄어쓰기는 빼고 칠한다.
            let lastCharacter = layout.characterIndexForGlyph(at: NSMaxRange(part) - 1)
            if let scalar = (self.stack.storage.string as NSString).substring(with: NSRange(location: lastCharacter, length: 1)).unicodeScalars.first,
               CharacterSet.whitespacesAndNewlines.contains(scalar), part.length > 1 {
                bounds = layout.boundingRect(forGlyphRange: NSRange(location: part.location, length: part.length - 1), in: container)
            }
            let baseline = lineRect.minY + layout.location(forGlyphAt: part.location).y
            result.append(LineSegment(
                rect: bounds.offsetBy(dx: self.origin.x, dy: self.origin.y),
                baseline: baseline + self.origin.y
            ))
        }
        return result
    }

    private func span(at position: ReadingPosition) -> ReaderSentenceSpan? {
        spans.first { $0.position == position }
    }

    private func wordRange(_ ref: ReaderTokenRef) -> NSRange? {
        guard let span = span(at: ref.position) else { return nil }
        let tokens = tokens(at: ref.position)
        guard tokens.indices.contains(ref.index) else { return nil }
        let token = tokens[ref.index]
        return NSRange(location: span.range.location + token.range.lowerBound, length: token.range.count)
    }

    /// 읽는 문장 칠 영역. 줄 높이 전체가 아니라 글자 높이에 맞춰 줄 사이가 조금 비게 한다.
    func sentenceRects(_ position: ReadingPosition) -> [CGRect] {
        guard let span = span(at: position) else { return [] }
        let pad = (metrics.fontSize * 0.16).rounded()
        return segments(for: span.range).map { segment in
            let top = segment.baseline - bodyFont.ascender - pad
            let bottom = segment.baseline - bodyFont.descender + pad
            return CGRect(x: segment.rect.minX - 3, y: top, width: segment.rect.width + 6, height: bottom - top)
        }
    }

    /// 단어 카드를 붙일 자리 (첫 줄).
    func wordRect(_ ref: ReaderTokenRef) -> CGRect? {
        guard let range = wordRange(ref), let first = segments(for: range).first else { return nil }
        return CGRect(x: first.rect.minX, y: first.baseline - bodyFont.ascender, width: first.rect.width, height: bodyFont.ascender - bodyFont.descender)
    }

    // MARK: 그리기

    /// 마일드 화면: 읽는 문장은 재생 중일 때만 연하게, 누른 단어는 카드가 열린 동안 옅은 선택 표시만 한다.
    /// 단어 색·밑줄은 바꾸지 않는다.
    func draw(in context: CGContext, state: ReaderPageDrawState) {
        if let highlight = state.highlight {
            context.setFillColor(ReaderPlatformColor(readerHex: palette.sentence).withAlphaComponent(0.55).cgColor)
            for rect in sentenceRects(highlight) { context.fill(rect) }
        }
        if let ref = state.activeWord, let rect = wordRect(ref) {
            context.setFillColor(ReaderPlatformColor(readerHex: palette.word).withAlphaComponent(0.18).cgColor)
            let selection = CGPath(roundedRect: rect.insetBy(dx: -3, dy: -2), cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.addPath(selection)
            context.fillPath()
        }

        let layout = stack.layoutManager
        let glyphs = layout.glyphRange(for: stack.container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: origin)

        context.setFillColor(ReaderPlatformColor(readerHex: palette.word).cgColor)
        for position in state.bookmarks {
            guard let first = sentenceRects(position).first else { continue }
            drawBookmark(in: context, x: max(4, metrics.marginX - 18), top: first.minY + 1)
        }
    }

    /// 여백의 북마크 표시: 아래가 V로 파인 평평한 띠.
    private func drawBookmark(in context: CGContext, x: CGFloat, top: CGFloat) {
        let width: CGFloat = 8
        let height = (metrics.fontSize * 0.8).rounded()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x + width, y: top))
        path.addLine(to: CGPoint(x: x + width, y: top + height))
        path.addLine(to: CGPoint(x: x + width / 2, y: top + height - 3))
        path.addLine(to: CGPoint(x: x, y: top + height))
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }
}

/// 문장 메뉴 항목. iPhone(길게 누르기)·Mac(우클릭)이 같은 목록을 쓴다.
struct ReaderSentenceMenuItem {
    var title: String
    var systemImage: String
    var isEnabled = true
    var perform: () -> Void
}

extension ReaderSession {
    func sentenceMenuItems(at position: ReadingPosition) -> [ReaderSentenceMenuItem] {
        let sentence = book.sentence(at: position)
        let revealed = isTranslationRevealed(at: position)
        let isBookmarked = bookmark(at: position) != nil
        var items = [
            ReaderSentenceMenuItem(
                title: revealed ? "번역 숨기기" : "번역 보기",
                systemImage: "character.bubble",
                isEnabled: sentence?.translation != nil
            ) { [weak self] in self?.toggleTranslation(at: position) },
            ReaderSentenceMenuItem(
                title: "이 문장부터 듣기",
                systemImage: "play",
                isEnabled: speaker.modelState == .ready
            ) { [weak self] in self?.play(from: position) },
            ReaderSentenceMenuItem(
                title: isBookmarked ? "북마크 삭제" : "북마크",
                systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
            ) { [weak self] in self?.toggleBookmark(at: position) },
        ]
        if let text = sentence?.text {
            items.append(ReaderSentenceMenuItem(title: "문장 복사", systemImage: "doc.on.doc") {
                ReaderPasteboard.copy(text)
            })
        }
        return items
    }
}

#if os(iOS)
/// iPhone 페이지 본문. 누르면 단어 카드, 길게 누르면 문장 메뉴(미리보기에 번역).
struct ReaderPageCanvas: UIViewRepresentable {
    let session: ReaderSession
    let text: ReaderPageText
    let state: ReaderPageDrawState
    /// 단어가 아닌 곳을 눌렀을 때 (막대 숨기기).
    var onBackgroundTap: () -> Void = {}

    func makeUIView(context: Context) -> ReaderPageCanvasView {
        ReaderPageCanvasView()
    }

    func updateUIView(_ view: ReaderPageCanvasView, context: Context) {
        view.session = session
        view.text = text
        view.state = state
        view.onBackgroundTap = onBackgroundTap
    }
}

final class ReaderPageCanvasView: UIView, UIContextMenuInteractionDelegate {
    var session: ReaderSession?
    var onBackgroundTap: () -> Void = {}
    var text: ReaderPageText? {
        didSet {
            guard text !== oldValue else { return }
            accessibilityLabel = text?.plainText
            setNeedsDisplay()
        }
    }
    var state = ReaderPageDrawState() {
        didSet { if state != oldValue { setNeedsDisplay() } }
    }
    private var menuPosition: ReadingPosition?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        text?.draw(in: context, state: state)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let text, let session, let hit = text.hit(at: recognizer.location(in: self)), let token = hit.token,
              let surface = text.tokens(at: hit.position)[token].surface
        else {
            onBackgroundTap()
            return
        }
        session.tapWord(surface, ref: ReaderTokenRef(position: hit.position, index: token))
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let text, let session, let hit = text.hit(at: location) else { return nil }
        let position = hit.position
        menuPosition = position
        let sentence = session.book.sentence(at: position)
        return UIContextMenuConfiguration(identifier: nil) {
            let controller = UIHostingController(rootView: ReaderSentencePreview(sentence: sentence))
            controller.sizingOptions = .preferredContentSize
            return controller
        } actionProvider: { _ in
            UIMenu(children: session.sentenceMenuItems(at: position).map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.systemImage),
                    attributes: item.isEnabled ? [] : .disabled
                ) { _ in item.perform() }
            })
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        sentencePreview()
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration, dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
        sentencePreview()
    }

    /// 들어 올릴 때 페이지 전체가 아니라 그 문장 줄만 보이게 한다.
    /// 이 뷰 자체를 넘기면 메뉴가 떠 있는 동안 페이지 글 전체가 숨겨지므로 사본을 넘긴다.
    private func sentencePreview() -> UITargetedPreview? {
        guard let text, let position = menuPosition, let snapshot = snapshotView(afterScreenUpdates: false) else { return nil }
        let rects = text.sentenceRects(position)
        guard !rects.isEmpty else { return nil }
        let parameters = UIPreviewParameters(textLineRects: rects.map { NSValue(cgRect: $0) })
        parameters.backgroundColor = UIColor(readerHex: text.palette.page)
        let target = UIPreviewTarget(container: self, center: CGPoint(x: bounds.midX, y: bounds.midY))
        return UITargetedPreview(view: snapshot, parameters: parameters, target: target)
    }
}
#else
/// Mac 페이지 본문. 클릭하면 단어 카드(팝오버는 `ReaderPageView` 가 붙인다), 우클릭은 문장 메뉴.
struct ReaderPageCanvas: NSViewRepresentable {
    let session: ReaderSession
    let text: ReaderPageText
    let state: ReaderPageDrawState
    /// 단어가 아닌 곳을 눌렀을 때 (막대 숨기기).
    var onBackgroundTap: () -> Void = {}

    func makeNSView(context: Context) -> ReaderPageCanvasView {
        ReaderPageCanvasView()
    }

    func updateNSView(_ view: ReaderPageCanvasView, context: Context) {
        view.session = session
        view.text = text
        view.state = state
        view.onBackgroundTap = onBackgroundTap
    }
}

final class ReaderPageCanvasView: NSView {
    var session: ReaderSession?
    var onBackgroundTap: () -> Void = {}
    var text: ReaderPageText? {
        didSet {
            guard text !== oldValue else { return }
            setAccessibilityValue(text?.plainText)
            needsDisplay = true
        }
    }
    var state = ReaderPageDrawState() {
        didSet { if state != oldValue { needsDisplay = true } }
    }
    private var mouseDownPoint: CGPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        text?.draw(in: context, state: state)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { mouseDownPoint = nil }
        guard let start = mouseDownPoint, hypot(point.x - start.x, point.y - start.y) < 4 else { return }
        guard let text, let session, let hit = text.hit(at: point), let token = hit.token,
              let surface = text.tokens(at: hit.position)[token].surface
        else {
            onBackgroundTap()
            return
        }
        session.tapWord(surface, ref: ReaderTokenRef(position: hit.position, index: token))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let text, let session, let hit = text.hit(at: point) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items = session.sentenceMenuItems(at: hit.position)
        for (index, item) in items.enumerated() {
            if index == items.count - 1, item.systemImage == "doc.on.doc" { menu.addItem(.separator()) }
            let target = ReaderMenuTarget(item.perform)
            let menuItem = NSMenuItem(title: item.title, action: #selector(ReaderMenuTarget.run), keyEquivalent: "")
            menuItem.target = target
            menuItem.representedObject = target
            menuItem.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
        return menu
    }
}

private final class ReaderMenuTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}
#endif
