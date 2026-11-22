import CoreGraphics
import Foundation
import PDFKit
import Vision

/// PDF → 중간 결과. 글자가 있는 페이지는 PDFKit, 글자가 없는 페이지(스캔본)는 Vision OCR.
/// 페이지마다 반복되는 머리말·꼬리말·쪽 번호를 지우고, 줄 끝 하이픈을 잇고, 줄 간격·들여쓰기로 문단을 나눈다.
nonisolated enum PDFBookParser {
    /// 이보다 글자가 적은 페이지는 스캔본으로 보고 OCR 한다.
    static let minimumTextLetters = 20

    static func parse(url: URL, progress: (@Sendable (ImportProgress) -> Void)? = nil) async throws -> ImportDraft {
        guard let document = PDFDocument(url: url) else { throw BookImportError.unreadable("PDF를 열 수 없음") }
        if document.isLocked { throw BookImportError.lockedPDF }

        var pages: [[PDFLine]] = []
        var ocrPages = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var lines = textLines(page)
            if lines.reduce(0, { $0 + $1.text.filter(\.isLetter).count }) < minimumTextLetters {
                progress?(ImportProgress(fraction: Double(index) / Double(document.pageCount), message: "글자 읽는 중(OCR) \(index + 1)/\(document.pageCount)쪽"))
                lines = try await recognizeLines(page)
                ocrPages += 1
            } else {
                progress?(ImportProgress(fraction: Double(index) / Double(document.pageCount), message: "본문 읽는 중 \(index + 1)/\(document.pageCount)쪽"))
            }
            pages.append(lines)
        }
        progress?(ImportProgress(fraction: 1, message: "본문 정리 중"))

        let attributes = document.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ImportDraft(title: title, author: author, declaredLanguage: nil, chapters: PDFLayout.chapters(pages: pages, bookTitle: title))
    }

    // MARK: Text layer

    /// PDFKit 글자 층의 줄. PDF마다 글자 위치(`characterBounds`, `selectionsByLine`)가 어긋나거나 문단 단위로 뭉쳐 있어
    /// 위치 대신 글로 줄 모양을 만든다: 가로 끝 = 줄 길이 / 보통 줄 길이, 빈 줄은 줄 간격 두 배.
    /// 150자가 넘는 줄은 PDFKit이 이미 이어 붙인 문단으로 본다.
    static func textLines(_ page: PDFPage) -> [PDFLine] {
        guard let string = page.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let rawLines = string.components(separatedBy: .newlines)
        let lengths = rawLines.map { $0.trimmingCharacters(in: .whitespaces).count }.filter { $0 > 0 && $0 <= paragraphLength }
        let typical = CGFloat(max(lengths.sorted().dropFirst(lengths.count * 4 / 5).first ?? 60, 20))
        let step: CGFloat = 0.01
        var y: CGFloat = 0
        var lines: [PDFLine] = []
        for raw in rawLines {
            let text = ImportedBookBuilder.normalizeWhitespace(raw)
            y += step
            guard !text.isEmpty else {
                y += step // 빈 줄 = 문단 사이
                continue
            }
            let width: CGFloat
            if text.count > paragraphLength {
                width = PDFLayout.endsSentence(text) ? 0.5 : 1
            } else {
                width = min(1, CGFloat(text.count) / typical)
            }
            let indent: CGFloat = raw.prefix { $0 == " " || $0 == "\t" || $0 == "\u{3000}" || $0 == "\u{2003}" }.isEmpty ? 0 : 0.05
            lines.append(PDFLine(text: text, minX: indent, maxX: indent + width * (1 - indent), top: y, bottom: y + step * 0.8))
        }
        return lines
    }

    private static let paragraphLength = 150

    // MARK: OCR

    static func recognizeLines(_ page: PDFPage) async throws -> [PDFLine] {
        guard let image = render(page) else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        // 기본값(1/32)은 책 본문 글자(쪽 높이의 1~2%)보다 커서 줄이 합쳐지거나 빠진다.
        request.minimumTextHeightFraction = 0.005
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            let rect = observation.boundingBox.cgRect // 0...1, 원점 왼쪽 아래
            return PDFLine(text: text, minX: rect.minX, maxX: rect.maxX, top: 1 - rect.maxY, bottom: 1 - rect.minY)
        }
        .sorted { $0.top < $1.top }
    }

    /// 페이지를 긴 변 약 2,400px 이미지로 그린다 (책 한 쪽 기준 300dpi 근처).
    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(4, 2400 / max(size.width, size.height))
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.concatenate(page.transform(for: .mediaBox))
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

/// 한 줄과 그 위치 (페이지 안 0...1, 위에서 아래).
nonisolated struct PDFLine: Equatable, Sendable {
    var text: String
    var minX: CGFloat
    var maxX: CGFloat
    var top: CGFloat
    var bottom: CGFloat
}

/// 페이지별 줄 → 장·문단. 위치 정보만 쓰므로 PDFKit·OCR 결과 모두 같은 규칙으로 정리한다.
nonisolated enum PDFLayout {
    static func chapters(pages: [[PDFLine]], bookTitle: String) -> [ImportDraftChapter] {
        let cleaned = removingRunningHeaders(pages)
        let paragraphs = paragraphs(pages: cleaned)

        var chapters: [ImportDraftChapter] = []
        var current = ImportDraftChapter(title: "", paragraphs: [])
        for paragraph in paragraphs {
            if paragraph.lineCount == 1, ChapterHeading.isNumbered(paragraph.text) || ChapterHeading.isAllCapsTitle(paragraph.text) {
                if current.paragraphs.isEmpty {
                    current.title = current.title.isEmpty ? paragraph.text : current.title + ". " + paragraph.text
                } else {
                    chapters.append(current)
                    current = ImportDraftChapter(title: paragraph.text, paragraphs: [])
                }
                continue
            }
            current.paragraphs.append(paragraph.text)
        }
        if !current.paragraphs.isEmpty { chapters.append(current) }
        for index in chapters.indices where chapters[index].title.isEmpty {
            chapters[index].title = index == 0 ? bookTitle : "Chapter \(index + 1)"
        }
        return chapters
    }

    // MARK: Running headers / footers

    /// 각 페이지 위·아래 두 줄 안에서 여러 페이지에 되풀이되는 줄(숫자는 무시)과 쪽 번호만 있는 줄을 지운다.
    static func removingRunningHeaders(_ pages: [[PDFLine]]) -> [[PDFLine]] {
        let edge = 2
        var counts: [String: Int] = [:]
        for lines in pages {
            var keys = Set<String>()
            for line in edgeLines(lines, edge: edge) { keys.insert(repeatKey(line.text)) }
            for key in keys { counts[key, default: 0] += 1 }
        }
        let threshold = max(2, Int((Double(pages.count) * 0.4).rounded(.up)))
        let repeated = Set(counts.filter { $0.value >= threshold && !$0.key.isEmpty }.keys)

        return pages.map { lines in
            lines.enumerated().filter { index, line in
                let atEdge = index < edge || index >= lines.count - edge
                guard atEdge else { return true }
                if isPageNumber(line.text) { return false }
                return !(pages.count >= 2 && repeated.contains(repeatKey(line.text)))
            }.map(\.element)
        }
    }

    private static func edgeLines(_ lines: [PDFLine], edge: Int) -> [PDFLine] {
        guard lines.count > edge * 2 else { return lines }
        return Array(lines.prefix(edge) + lines.suffix(edge))
    }

    /// 숫자를 #로, 공백·대소문자 무시.
    static func repeatKey(_ text: String) -> String {
        String(text.lowercased().compactMap { character -> Character? in
            if character.isNumber { return "#" }
            if character.isWhitespace { return nil }
            return character
        })
    }

    private static let pageNumberPattern = try! NSRegularExpression(
        pattern: "^[-–—\\s]*(page\\s+)?([0-9]{1,4}|[ivxlcdm]{1,7})[-–—\\s]*$", options: [.caseInsensitive]
    )

    static func isPageNumber(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return pageNumberPattern.firstMatch(in: text, range: range) != nil
    }

    // MARK: Paragraphs

    struct Paragraph: Equatable {
        var text: String
        var lineCount: Int
    }

    /// 줄 간격이 평소보다 크거나, 첫 줄 들여쓰기가 있거나, 앞 줄이 짧게 문장으로 끝나면 새 문단.
    static func paragraphs(pages: [[PDFLine]]) -> [Paragraph] {
        let allLines = pages.flatMap { $0 }
        guard !allLines.isEmpty else { return [] }
        let leftMargin = median(allLines.map(\.minX))
        // 문단 끝 줄은 짧으므로 오른쪽 끝은 중앙값이 아니라 위쪽 20% 값으로 본다.
        let rightMargin = quantile(allLines.map(\.maxX), 0.8)
        let lineWidth = max(rightMargin - leftMargin, 0.01)
        let pitches = pages.flatMap { lines in
            zip(lines, lines.dropFirst()).map { $1.top - $0.top }.filter { $0 > 0 }
        }
        let pitch = median(pitches)

        var result: [Paragraph] = []
        var text = ""
        var lineCount = 0
        func flush() {
            let paragraph = ImportedBookBuilder.normalizeWhitespace(text)
            if !paragraph.isEmpty { result.append(Paragraph(text: paragraph, lineCount: lineCount)) }
            text = ""
            lineCount = 0
        }

        func append(_ line: String) {
            if text.isEmpty {
                text = line
            } else if endsWithBrokenHyphen(text), let first = line.first, first.isLowercase {
                text.removeLast()
                text += line
            } else {
                text += " " + line
            }
        }

        var previous: PDFLine?
        for lines in pages {
            for (index, line) in lines.enumerated() {
                if let previous {
                    let samePage = index > 0
                    let gap = samePage ? line.top - previous.top : 0
                    let bigGap = samePage && pitch > 0 && gap > pitch * 1.6
                    let indented = line.minX - leftMargin > lineWidth * 0.03 && line.minX - leftMargin < lineWidth * 0.25
                    let previousShort = previous.maxX < leftMargin + lineWidth * 0.8
                    let previousEndsSentence = endsSentence(previous.text)
                    let centered = line.minX - leftMargin > lineWidth * 0.25
                    // 들여쓰기만으로는 OCR 흔들림일 수 있어 앞 줄이 문장 끝이거나 짧을 때만 새 문단으로 본다.
                    if bigGap || (indented && (previousEndsSentence || previousShort)) || (previousShort && previousEndsSentence) || centered
                        || isLikelyHeading(previous) || isLikelyHeading(line) {
                        flush()
                    }
                }
                append(line.text)
                lineCount += 1
                previous = line
            }
        }
        flush()
        return result
    }

    private static func isLikelyHeading(_ line: PDFLine) -> Bool {
        ChapterHeading.isNumbered(line.text) || ChapterHeading.isAllCapsTitle(line.text)
    }

    /// 줄 끝이 `글자-` 로 끝나 다음 줄과 이어지는 낱말인지 (`manage-` + `ment`). `--`(대시)는 제외.
    /// 다음 줄이 소문자로 시작할 때만 잇는 것은 부르는 쪽에서 본다 (`well-` + `Known` 은 그대로).
    static func endsWithBrokenHyphen(_ text: String) -> Bool {
        guard text.hasSuffix("-"), !text.hasSuffix("--") else { return false }
        return text.dropLast().last?.isLetter == true
    }

    static func endsSentence(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        while let last = trimmed.last, "\"'”’)]".contains(last) { trimmed.removeLast() }
        guard let last = trimmed.last else { return false }
        return ".!?:;…".contains(last)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        quantile(values, 0.5)
    }

    private static func quantile(_ values: [CGFloat], _ q: Double) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))]
    }
}

/// "Chapter 1", "CHAPTER IV. The Storm", "II." 같은 장 제목 줄 알아보기. 영어 책 전용 규칙.
nonisolated enum ChapterHeading {
    private static let numberWords = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|last"
    private static let roman = "(?=[ivxlcdm])m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3})"
    /// 1: 낱말, 2: 번호 (없을 수 있음), 3: 나머지 제목
    private static let numbered = try! NSRegularExpression(
        pattern: "^(chapter|book|part|section|story|letter|prologue|epilogue)(?:\\s+([0-9]{1,3}|\(roman)|(?:\(numberWords))(?:-(?:\(numberWords)))?)\\b)?[\\s.:—–-]*(.{0,80})$",
        options: [.caseInsensitive]
    )
    private static let romanOnly = try! NSRegularExpression(pattern: "^[IVXLC]{1,7}\\.?$")
    private static let digitsOnly = try! NSRegularExpression(pattern: "^[0-9]{1,3}\\.?$")

    /// 번호가 붙은 장 제목("Chapter 3", "II.", "Prologue")이면 true.
    static func isNumbered(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line.count <= 90 else { return false }
        let range = NSRange(line.startIndex..., in: line)
        if romanOnly.firstMatch(in: line, range: range) != nil { return true }
        if digitsOnly.firstMatch(in: line, range: range) != nil { return true }
        guard let match = numbered.firstMatch(in: line, range: range) else { return false }
        let keyword = (line as NSString).substring(with: match.range(at: 1)).lowercased()
        if keyword == "prologue" || keyword == "epilogue" {
            return match.range(at: 3).length <= 40
        }
        // "Chapter"·"Part" 등은 번호가 있어야 장 제목이다.
        let number = match.range(at: 2)
        return number.location != NSNotFound && number.length > 0
    }

    /// 대문자로만 쓴 짧은 줄 (단편집의 작품 제목 "THE GIFT OF THE MAGI").
    static func isAllCapsTitle(_ line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard line.count >= 3, line.count <= 70 else { return false }
        // 따옴표로 시작하면 대사·편지 글이다 (“BALLARAT.”).
        if let first = line.first, "“\"‘'".contains(first) { return false }
        let words = line.split(separator: " ")
        guard words.count <= 10 else { return false }
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3 else { return false }
        let uppercase = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        guard uppercase.count == letters.count else { return false }
        // 문장처럼 끝나면 제목이 아니다 ("STOP!" 같은 외침은 제외).
        return !(line.hasSuffix("!") || line.hasSuffix("?") || line.hasSuffix(","))
    }
}
