import CoreText
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 페이지 한 장의 치수. 마일드 화면에서는 화면(창) 하나가 페이지 하나다.
nonisolated struct ReaderPageMetrics: Hashable, Sendable {
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var marginX: CGFloat
    var marginTop: CGFloat
    var marginBottom: CGFloat
    var fontSize: CGFloat
    var lineHeight: CGFloat

    var bodyWidth: CGFloat { pageWidth - marginX * 2 }
    var bodyHeight: CGFloat { pageHeight - marginTop - marginBottom }
    var bodyOrigin: CGPoint { CGPoint(x: marginX, y: marginTop) }
    /// 왼쪽 위 쪽 번호의 위쪽 y.
    var pageNumberTop: CGFloat { max(10, marginTop - 30) }

    /// 화면 크기 페이지.
    /// - Parameters:
    ///   - safeTop/safeBottom: 상태 막대·홈 표시 높이. 글이 그 아래·위에 놓인다.
    ///   - minMarginX: 좌우 최소 여백 (iPhone 24pt).
    ///   - maxBodyWidth: 본문 열 최대 폭 (Mac 약 70자). nil이면 제한 없음.
    static func screen(
        size: CGSize,
        safeTop: CGFloat = 0,
        safeBottom: CGFloat = 0,
        minMarginX: CGFloat = 24,
        maxBodyWidth: CGFloat? = nil,
        fontSize: CGFloat,
        lineHeight: CGFloat
    ) -> ReaderPageMetrics {
        let width = size.width.rounded()
        var marginX = minMarginX
        if let maxBodyWidth, width - minMarginX * 2 > maxBodyWidth {
            marginX = ((width - maxBodyWidth) / 2).rounded()
        }
        return ReaderPageMetrics(
            pageWidth: width,
            pageHeight: size.height.rounded(),
            marginX: marginX,
            marginTop: (safeTop + 40).rounded(),
            marginBottom: (safeBottom + 28).rounded(),
            fontSize: fontSize,
            lineHeight: lineHeight
        )
    }

    /// 본문 열 최대 폭: 한 줄 약 70자 (세리프 평균 글자 폭 ≈ 0.5em).
    static func readableBodyWidth(fontSize: CGFloat) -> CGFloat {
        (fontSize * 35).rounded()
    }
}

/// 페이지 안의 한 덩어리.
nonisolated enum ReaderPageBlock: Hashable, Sendable {
    /// 장 첫 페이지의 가운데 장 제목.
    case chapterTitle(chapter: Int)
    /// 문단 전체 또는 문장 경계에서 잘린 일부. `indented` 는 첫 줄 들여쓰기.
    case paragraph(chapter: Int, paragraph: Int, sentences: Range<Int>, indented: Bool)
}

nonisolated struct ReaderPage: Identifiable, Hashable, Sendable {
    var index: Int
    var chapter: Int
    var blocks: [ReaderPageBlock]
    /// 이 페이지의 문장, 본문 순서대로.
    var positions: [ReadingPosition]
    /// 각 문장 첫 줄의 위쪽 y (본문 영역 기준). `positions` 와 같은 순서.
    var sentenceTops: [CGFloat]

    var id: Int { index }
    var firstPosition: ReadingPosition? { positions.first }

    func top(of position: ReadingPosition) -> CGFloat? {
        positions.firstIndex(of: position).map { sentenceTops[$0] }
    }
}

/// 본문 안 문장 하나의 글자 범위.
nonisolated struct ReaderSentenceSpan: Hashable, Sendable {
    var position: ReadingPosition
    var range: NSRange
}

/// 페이지 덩어리를 조판용 글(`NSAttributedString`)로 만든다. 페이지 나누기와 화면 그리기가 같은 것을 써서
/// 측정한 대로 그려진다. 본문은 세리프, 양쪽 정렬 + 하이픈, 문단 첫 줄 들여쓰기 1.4em.
nonisolated struct ReaderPageComposer {
    let book: BookDocument
    let fontSize: CGFloat
    let lineHeight: CGFloat
    var textColor: ReaderPlatformColor
    var secondaryColor: ReaderPlatformColor

    let bodyFont: ReaderPlatformFont
    private let titleFont: ReaderPlatformFont
    private let labelFont: ReaderPlatformFont

    init(
        book: BookDocument,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        textColor: ReaderPlatformColor = .black,
        secondaryColor: ReaderPlatformColor = .gray
    ) {
        self.book = book
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.textColor = textColor
        self.secondaryColor = secondaryColor
        bodyFont = Self.serifFont(size: fontSize, bold: false)
        titleFont = Self.serifFont(size: (fontSize * 1.45).rounded(), bold: true)
        labelFont = ReaderPlatformFont.systemFont(ofSize: max(10, (fontSize * 0.62).rounded()), weight: .semibold)
    }

    /// Iowan Old Style, 없으면 시스템 세리프(New York).
    static func serifFont(size: CGFloat, bold: Bool) -> ReaderPlatformFont {
        if let font = ReaderPlatformFont(name: bold ? "IowanOldStyle-Bold" : "IowanOldStyle-Roman", size: size) {
            return font
        }
        let base = ReaderPlatformFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        #if os(macOS)
        if let descriptor = base.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        #else
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        #endif
        return base
    }

    private var languageKey: NSAttributedString.Key { NSAttributedString.Key(kCTLanguageAttributeName as String) }

    private func bodyAttributes(indented: Bool) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.hyphenationFactor = 1
        style.lineHeightMultiple = lineHeight
        style.firstLineHeadIndent = indented ? (fontSize * 1.4).rounded() : 0
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: style,
            // 하이픈 사전을 고르려면 글의 언어가 필요하다. 기기 언어(한국어)로 두면 영어를 끊지 못한다.
            languageKey: book.language,
        ]
    }

    func appendChapterTitle(_ chapter: Int, to text: NSMutableAttributedString) {
        let label = NSMutableParagraphStyle()
        label.alignment = .center
        label.paragraphSpacing = fontSize * 0.5
        let title = NSMutableParagraphStyle()
        title.alignment = .center
        title.lineHeightMultiple = 1.15
        title.paragraphSpacing = (fontSize * lineHeight * 1.6).rounded()

        appendParagraphBreakIfNeeded(to: text)
        text.append(NSAttributedString(string: "CHAPTER \(chapter + 1)", attributes: [
            .font: labelFont,
            .foregroundColor: secondaryColor,
            .kern: fontSize * 0.12,
            .paragraphStyle: label,
        ]))
        text.append(NSAttributedString(string: "\n", attributes: [.font: labelFont, .paragraphStyle: label]))
        text.append(NSAttributedString(string: book.chapters[chapter].title, attributes: [
            .font: titleFont,
            .foregroundColor: textColor,
            .paragraphStyle: title,
            languageKey: book.language,
        ]))
    }

    /// 문장 하나를 붙인다. `startsParagraph` 면 새 문단으로, 아니면 앞 문장 뒤에 띄어 붙인다.
    @discardableResult
    func appendSentence(
        _ position: ReadingPosition,
        startsParagraph: Bool,
        indented: Bool,
        to text: NSMutableAttributedString
    ) -> ReaderSentenceSpan? {
        guard let sentence = book.sentence(at: position) else { return nil }
        let attributes: [NSAttributedString.Key: Any]
        if startsParagraph {
            appendParagraphBreakIfNeeded(to: text)
            attributes = bodyAttributes(indented: indented)
        } else {
            attributes = text.length > 0 ? text.attributes(at: text.length - 1, effectiveRange: nil) : bodyAttributes(indented: false)
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }
        let start = text.length
        text.append(NSAttributedString(string: sentence.text, attributes: attributes))
        return ReaderSentenceSpan(position: position, range: NSRange(location: start, length: text.length - start))
    }

    /// 문단 끝 줄바꿈은 앞 문단의 속성으로 붙인다. 문단 모양은 그 문단의 글자를 따르기 때문이다.
    private func appendParagraphBreakIfNeeded(to text: NSMutableAttributedString) {
        guard text.length > 0 else { return }
        let attributes = text.attributes(at: text.length - 1, effectiveRange: nil)
        text.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    func compose(_ blocks: [ReaderPageBlock]) -> (NSMutableAttributedString, [ReaderSentenceSpan]) {
        let text = NSMutableAttributedString()
        var spans: [ReaderSentenceSpan] = []
        for block in blocks {
            switch block {
            case .chapterTitle(let chapter):
                appendChapterTitle(chapter, to: text)
            case .paragraph(let chapter, let paragraph, let sentences, let indented):
                for sentence in sentences {
                    let position = ReadingPosition(chapter: chapter, paragraph: paragraph, sentence: sentence)
                    if let span = appendSentence(
                        position,
                        startsParagraph: sentence == sentences.lowerBound,
                        indented: indented && sentence == sentences.lowerBound,
                        to: text
                    ) {
                        spans.append(span)
                    }
                }
            }
        }
        return (text, spans)
    }
}

/// TextKit 조판 한 벌. 페이지 나누기와 화면 그리기가 같이 쓴다.
nonisolated final class ReaderTextStack {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let container: NSTextContainer

    init(width: CGFloat) {
        container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    var usedHeight: CGFloat {
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height
    }

    /// 글자 위치가 들어 있는 줄의 위쪽 y.
    func lineTop(atCharacter index: Int) -> CGFloat {
        layoutManager.ensureLayout(for: container)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }
}

/// 책을 페이지로 나눈다. 장은 새 페이지에서 시작하고, 넘치면 **문장 경계**에서 다음 페이지로 넘긴다.
/// 문장은 쪼개지 않는다 (위치·하이라이트·북마크가 문장 단위라서).
nonisolated enum ReaderPaginator {
    static func paginate(book: BookDocument, metrics: ReaderPageMetrics) -> [ReaderPage] {
        let composer = ReaderPageComposer(book: book, fontSize: metrics.fontSize, lineHeight: metrics.lineHeight)
        let stack = ReaderTextStack(width: metrics.bodyWidth)
        let limit = metrics.bodyHeight + 0.5

        var pages: [ReaderPage] = []
        var blocks: [ReaderPageBlock] = []
        var spans: [ReaderSentenceSpan] = []
        var pageChapter = 0

        func closePage() {
            guard !blocks.isEmpty else { return }
            let tops = spans.map { stack.lineTop(atCharacter: $0.range.location) }
            pages.append(ReaderPage(
                index: pages.count,
                chapter: pageChapter,
                blocks: blocks,
                positions: spans.map(\.position),
                sentenceTops: tops
            ))
            stack.storage.setAttributedString(NSAttributedString())
            blocks = []
            spans = []
        }

        for chapter in book.chapters.indices {
            closePage()
            pageChapter = chapter
            if !book.chapters[chapter].title.isEmpty {
                composer.appendChapterTitle(chapter, to: stack.storage)
                blocks.append(.chapterTitle(chapter: chapter))
            }
            for paragraph in book.chapters[chapter].paragraphs.indices {
                for sentence in book.chapters[chapter].paragraphs[paragraph].sentences.indices {
                    let position = ReadingPosition(chapter: chapter, paragraph: paragraph, sentence: sentence)
                    // 장 첫 문단은 들여쓰지 않는다. 앞 페이지에서 이어지는 문단도 들여쓰지 않는다.
                    let indentsParagraph = sentence == 0 && paragraph > 0
                    var continues = false
                    if case .paragraph(chapter, paragraph, _, _)? = blocks.last { continues = true }

                    let before = stack.storage.length
                    var span = composer.appendSentence(
                        position, startsParagraph: !continues, indented: !continues && indentsParagraph, to: stack.storage
                    )
                    if stack.usedHeight > limit, !spans.isEmpty {
                        // 넘친다: 이 문장을 빼고 페이지를 닫은 뒤 새 페이지에서 시작한다.
                        stack.storage.deleteCharacters(in: NSRange(location: before, length: stack.storage.length - before))
                        closePage()
                        pageChapter = chapter
                        continues = false
                        span = composer.appendSentence(
                            position, startsParagraph: true, indented: indentsParagraph, to: stack.storage
                        )
                    }
                    guard let span else { continue }
                    if continues, case .paragraph(let c, let p, let range, let indented)? = blocks.last {
                        blocks[blocks.count - 1] = .paragraph(chapter: c, paragraph: p, sentences: range.lowerBound..<(sentence + 1), indented: indented)
                    } else {
                        blocks.append(.paragraph(chapter: chapter, paragraph: paragraph, sentences: sentence..<(sentence + 1), indented: indentsParagraph))
                    }
                    spans.append(span)
                }
            }
        }
        closePage()
        return pages
    }
}
