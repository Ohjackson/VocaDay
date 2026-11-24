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
    /// 여러 단어를 골랐으면 마지막 단어.
    var activeWordEnd: Int?
    /// 끌어 고르는 중인 범위.
    var phraseDraft: ReaderPhraseRange?
    /// 문장 카드가 열린 문장.
    var activeSentence: ReadingPosition?
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
        var local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        layout.ensureLayout(for: stack.container)
        let used = layout.usedRect(for: stack.container)
        guard local.y >= -4, local.y <= used.maxY + 4, local.x >= -8, local.x <= metrics.bodyWidth + 8 else { return nil }
        local.y = nearestLineCenter(to: local.y)

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

    /// 줄 높이 배수(`lineHeightMultiple`)는 남는 높이를 글자 위에 둔다. 그래서 글자 바로 아래를 누르면
    /// 다음 줄의 칸에 들어가 아랫 문장이 잡혔다. 칸이 아니라 눈에 보이는 글자 줄 중 가장 가까운 줄로 맞춘다.
    private func nearestLineCenter(to y: CGFloat) -> CGFloat {
        let layout = stack.layoutManager
        var best: (distance: CGFloat, center: CGFloat)?
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { lineRect, _, _, glyphs, _ in
            let baseline = lineRect.minY + layout.location(forGlyphAt: glyphs.location).y
            let center = baseline - (self.bodyFont.ascender + self.bodyFont.descender) / 2
            let distance = abs(y - center)
            if best == nil || distance < best!.distance { best = (distance, center) }
        }
        return best?.center ?? y
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

    /// 이어진 단어들(`from`…`to`)이 걸친 줄마다의 글자 영역.
    func selectionRects(_ position: ReadingPosition, from: Int, to: Int) -> [CGRect] {
        guard let span = span(at: position) else { return [] }
        let tokens = tokens(at: position)
        let lowerIndex = min(from, to), upperIndex = max(from, to)
        guard tokens.indices.contains(lowerIndex), tokens.indices.contains(upperIndex) else { return [] }
        let lower = span.range.location + tokens[lowerIndex].range.lowerBound
        let upper = span.range.location + tokens[upperIndex].range.upperBound
        return segments(for: NSRange(location: lower, length: upper - lower)).map { segment in
            CGRect(
                x: segment.rect.minX,
                y: segment.baseline - bodyFont.ascender,
                width: segment.rect.width,
                height: bodyFont.ascender - bodyFont.descender
            )
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
        let selection: [CGRect]
        if let draft = state.phraseDraft {
            selection = selectionRects(draft.position, from: draft.from, to: draft.to)
        } else if let ref = state.activeWord {
            selection = selectionRects(ref.position, from: ref.index, to: state.activeWordEnd ?? ref.index)
        } else if let position = state.activeSentence {
            selection = sentenceRects(position).map { $0.insetBy(dx: 3, dy: 0) }
        } else {
            selection = []
        }
        if !selection.isEmpty {
            context.setFillColor(ReaderPlatformColor(readerHex: palette.word).withAlphaComponent(0.18).cgColor)
            for rect in selection {
                context.addPath(CGPath(roundedRect: rect.insetBy(dx: -3, dy: -2), cornerWidth: 3, cornerHeight: 3, transform: nil))
            }
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

#if os(macOS)
/// Mac 우클릭 문장 메뉴 항목. iPhone은 길게 누르면 문장 카드(`ReaderSentenceCard`)가 뜬다.
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
#endif

#if os(iOS)
/// iPhone 페이지 본문. 누르면 단어 카드, 길게 누르면 문장 카드.
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

final class ReaderPageCanvasView: UIView, UIGestureRecognizerDelegate {
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
    /// 끌어 고르기를 시작한 단어.
    private var phraseAnchor: ReaderTokenRef?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        // 단어를 잠깐 누른 채 옆 단어로 끌면 여러 단어를 고른다. 움직이지 않고 더 누르면 문장 카드가 뜬다.
        // 바로 끌면(페이지 넘기기) 시작하지 않고, 끄는 동안은 `isDraggingSelection`으로 페이지가 넘어가지 않는다.
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.delegate = self
        addGestureRecognizer(drag)
        phraseDrag = drag
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        addGestureRecognizer(press)
        sentencePress = press
    }

    /// 손가락을 댄 시각과 자리. 끌기를 시작할 때 "단어를 잠깐 누르고 있었는지"를 본다.
    private var touchDown: (time: TimeInterval, point: CGPoint)?
    private var phraseDrag: UIPanGestureRecognizer?
    private var sentencePress: UILongPressGestureRecognizer?
    private static let holdBeforeDrag: TimeInterval = 0.2

    /// `touchesBegan`은 스크롤 뷰가 늦추거나 건너뛰어서, 지난 터치의 시각이 남아 스와이프가 끌어 고르기로 잡혔다.
    /// 인식기가 터치를 받는 순간은 빠지지 않는다.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer === phraseDrag { touchDown = (touch.timestamp, touch.location(in: self)) }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === sentencePress {
            return text?.hit(at: gestureRecognizer.location(in: self)) != nil
        }
        guard gestureRecognizer === phraseDrag else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard let touchDown, ProcessInfo.processInfo.systemUptime - touchDown.time >= Self.holdBeforeDrag,
              let hit = text?.hit(at: touchDown.point), hit.token != nil
        else { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let text, let session else { return }
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard let start = touchDown?.point, let hit = text.hit(at: start), let token = hit.token else { return }
            phraseAnchor = ReaderTokenRef(position: hit.position, index: token)
            session.isDraggingSelection = true
            sentencePress?.cancel()
            fallthrough
        case .changed:
            // 문장을 넘어가면 마지막으로 고른 범위를 그대로 둔다.
            guard let anchor = phraseAnchor, let hit = text.hit(at: point), hit.position == anchor.position,
                  let token = hit.token else { return }
            session.phraseDraft = token == anchor.index
                ? nil
                : ReaderPhraseRange(position: anchor.position, from: min(anchor.index, token), to: max(anchor.index, token))
        case .ended:
            if let draft = session.phraseDraft { session.selectPhrase(draft) }
            endPhraseDrag()
        default:
            endPhraseDrag()
        }
    }

    @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let text, let session else { return }
        let point = recognizer.location(in: self)
        guard let hit = text.hit(at: point) else { return }
        // 카드가 뜬 뒤 손가락이 움직여도 구절 선택으로 이어지지 않게 한다.
        phraseDrag?.cancel()
        let rects = text.sentenceRects(hit.position)
        let line = rects.indices.min { abs(rects[$0].midY - point.y) < abs(rects[$1].midY - point.y) } ?? 0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        session.pressSentence(ReaderActiveSentence(position: hit.position, page: text.page.index, line: line))
    }

    private func endPhraseDrag() {
        phraseAnchor = nil
        session?.phraseDraft = nil
        session?.isDraggingSelection = false
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
}

private extension UIGestureRecognizer {
    /// 지금 손가락에 대해서만 인식을 그만둔다.
    func cancel() {
        isEnabled = false
        isEnabled = true
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

    /// 단어에서 시작해 옆 단어로 끌면 여러 단어를 고른다.
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let text, let session,
              let anchor = text.hit(at: start), let from = anchor.token else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = text.hit(at: point), hit.position == anchor.position, let to = hit.token else { return }
        session.phraseDraft = from == to
            ? nil
            : ReaderPhraseRange(position: anchor.position, from: min(from, to), to: max(from, to))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { mouseDownPoint = nil }
        if let draft = session?.phraseDraft {
            session?.phraseDraft = nil
            session?.selectPhrase(draft)
            return
        }
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
