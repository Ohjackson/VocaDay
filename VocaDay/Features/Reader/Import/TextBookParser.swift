import Foundation

/// TXT 파일 → 중간 결과(장 → 문단). 문장 나누기·언어·책 ID는 PDF와 같이 `ImportedBookBuilder` 가 한다.
///
/// - 문단: 빈 줄로 나눈다. 문단 안의 줄바꿈은 줄 맞춤(하드 랩)으로 보고 이어 붙인다.
/// - 장: 한 줄짜리 문단이 "Chapter 3", "II.", "THE GIFT OF THE MAGI" 같은 장 제목이면 거기서 새 장을 연다.
///   장 제목이 없으면 책 전체가 한 장이다.
/// - 구텐베르크 책의 머리말·꼬리말(`*** START OF … ***`, `*** END OF … ***`)은 뺀다.
nonisolated enum TextBookParser {
    static func parse(url: URL) throws -> ImportDraft {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BookImportError.unreadable(error.localizedDescription)
        }
        guard let text = decode(data) else { throw BookImportError.unreadable("글자 인코딩을 알 수 없어요") }
        let title = url.deletingPathExtension().lastPathComponent
        return parse(text: text, title: title)
    }

    static func parse(text: String, title: String) -> ImportDraft {
        let body = strippingGutenbergFrame(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var chapters: [ImportDraftChapter] = [ImportDraftChapter(title: "", paragraphs: [])]
        for block in blocks(body) {
            if block.count == 1, isHeading(block[0]) {
                chapters.append(ImportDraftChapter(title: block[0], paragraphs: []))
            } else {
                chapters[chapters.count - 1].paragraphs.append(joinLines(block))
            }
        }
        // 첫 장 제목 앞의 짧은 머리글(책 제목·지은이 한두 줄)은 장으로 만들지 않는다.
        if chapters.count > 1, let front = chapters.first, front.paragraphs.count <= 2,
           front.paragraphs.allSatisfy({ $0.count <= 80 }) {
            chapters.removeFirst()
        }
        return ImportDraft(title: title, author: nil, declaredLanguage: nil, chapters: chapters)
    }

    /// UTF-8 → UTF-16(BOM) → Windows-1252 순서로 읽어 본다.
    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return text }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// 빈 줄로 나눈 덩어리. 덩어리마다 앞뒤 공백을 뺀 줄 목록.
    private static func blocks(_ text: String) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { result.append(current) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 줄을 띄어 잇는다. 줄 끝 `manage-` + 소문자로 시작하는 다음 줄은 붙여 잇는다.
    private static func joinLines(_ lines: [String]) -> String {
        var text = ""
        for line in lines {
            if text.isEmpty {
                text = line
            } else if PDFLayout.endsWithBrokenHyphen(text), line.first?.isLowercase == true {
                text.removeLast()
                text += line
            } else {
                text += " " + line
            }
        }
        return text
    }

    private static func isHeading(_ line: String) -> Bool {
        ChapterHeading.isNumbered(line) || ChapterHeading.isAllCapsTitle(line)
    }

    private static func strippingGutenbergFrame(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.hasPrefix("*** START OF") }) {
            lines.removeSubrange(...start)
        }
        if let end = lines.firstIndex(where: { $0.hasPrefix("*** END OF") }) {
            lines.removeSubrange(end...)
        }
        return lines.joined(separator: "\n")
    }
}
