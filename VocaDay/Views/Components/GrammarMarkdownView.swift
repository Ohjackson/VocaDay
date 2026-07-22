import SwiftUI

struct GrammarMarkdownView: View {
    let markdown: String

    private var blocks: [GrammarMarkdownBlock] {
        GrammarMarkdownParser.parse(markdown)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: GrammarMarkdownBlock) -> some View {
        switch block.kind {
        case .heading1(let text):
            Text(markdownText(text))
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading2(let text):
            Text(markdownText(text))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .heading3(let text):
            Text(markdownText(text))
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(markdownText(text))
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(markdownText(text))
                    .font(.body)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .callout(let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
                    .padding(.top, 2)

                Text(markdownText(text))
                    .font(.callout)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.yellow.opacity(0.24))
            }
        case .table(let rows):
            grammarTable(rows)
        case .divider:
            Divider()
                .padding(.vertical, 8)
        }
    }

    private func grammarTable(_ rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(markdownText(cell))
                                .font(rowIndex == 0 ? .caption.weight(.semibold) : .subheadline)
                                .foregroundStyle(rowIndex == 0 ? .secondary : .primary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 118, maxWidth: 190, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(rowIndex == 0 ? Color.secondary.opacity(0.08) : Color.clear)
                                .overlay(alignment: .trailing) {
                                    Rectangle()
                                        .fill(AppTheme.softStroke)
                                        .frame(width: 0.5)
                                }
                        }
                    }

                    Divider()
                }
            }
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.softStroke)
            }
        }
    }

    private func markdownText(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct GrammarMarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading1(String)
        case heading2(String)
        case heading3(String)
        case paragraph(String)
        case bullet(String)
        case callout(String)
        case table([[String]])
        case divider
    }
}

private enum GrammarMarkdownParser {
    static func parse(_ markdown: String) -> [GrammarMarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [GrammarMarkdownBlock] = []
        var paragraph: [String] = []
        var tableRows: [[String]] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: "\n")
            blocks.append(block(forParagraph: text))
            paragraph.removeAll()
        }

        func flushTable() {
            guard !tableRows.isEmpty else { return }
            blocks.append(GrammarMarkdownBlock(kind: .table(tableRows)))
            tableRows.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty else {
                flushParagraph()
                flushTable()
                continue
            }

            if line == "---" || line == "***" {
                flushParagraph()
                flushTable()
                blocks.append(GrammarMarkdownBlock(kind: .divider))
                continue
            }

            if isTableLine(line) {
                flushParagraph()
                if !isAlignmentTableLine(line) {
                    tableRows.append(tableCells(from: line))
                }
                continue
            }

            flushTable()

            if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(GrammarMarkdownBlock(kind: .heading3(String(line.dropFirst(4)))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(GrammarMarkdownBlock(kind: .heading2(String(line.dropFirst(3)))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(GrammarMarkdownBlock(kind: .heading1(String(line.dropFirst(2)))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(GrammarMarkdownBlock(kind: .bullet(String(line.dropFirst(2)))))
            } else {
                paragraph.append(line)
            }
        }

        flushParagraph()
        flushTable()

        return blocks
    }

    private static func block(forParagraph text: String) -> GrammarMarkdownBlock {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("**핵심:**") ||
            trimmed.hasPrefix("**Key:**") ||
            trimmed.hasPrefix("핵심:") ||
            trimmed.hasPrefix("Key:") ||
            trimmed.hasPrefix("주의:") {
            return GrammarMarkdownBlock(kind: .callout(trimmed))
        }

        return GrammarMarkdownBlock(kind: .paragraph(trimmed))
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|")
    }

    private static func isAlignmentTableLine(_ line: String) -> Bool {
        let trimmed = line.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
    }

    private static func tableCells(from line: String) -> [String] {
        var trimmed = line
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
