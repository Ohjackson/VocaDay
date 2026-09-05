import Foundation
import SwiftData

enum StudyPageBlockKind: String, Codable, CaseIterable, Identifiable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletedList
    case numberedList
    case toDo
    case toggle
    case quote
    case callout
    case code
    case divider
    case table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "텍스트"
        case .heading1: "제목 1"
        case .heading2: "제목 2"
        case .heading3: "제목 3"
        case .bulletedList: "글머리 기호 목록"
        case .numberedList: "번호 목록"
        case .toDo: "할 일 목록"
        case .toggle: "토글 목록"
        case .quote: "인용"
        case .callout: "콜아웃"
        case .code: "코드"
        case .divider: "구분선"
        case .table: "표"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .heading3: "textformat"
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .toDo: "checkmark.square"
        case .toggle: "chevron.right"
        case .quote: "quote.opening"
        case .callout: "lightbulb"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .table: "tablecells"
        }
    }

    var helpText: String {
        switch self {
        case .text: "일반 문장을 작성합니다."
        case .heading1: "페이지의 가장 큰 구역 제목입니다."
        case .heading2: "중간 크기의 구역 제목입니다."
        case .heading3: "작은 구역 제목입니다."
        case .bulletedList: "순서가 없는 목록을 만듭니다."
        case .numberedList: "순서가 있는 목록을 만듭니다."
        case .toDo: "완료 여부를 표시할 수 있습니다."
        case .toggle: "내용을 접고 펼칠 수 있습니다."
        case .quote: "중요한 문장이나 예문을 강조합니다."
        case .callout: "암기할 내용이나 주의점을 강조합니다."
        case .code: "고정폭 글꼴로 내용을 기록합니다."
        case .divider: "내용 사이에 구분선을 추가합니다."
        case .table: "행과 열로 정보를 정리합니다."
        }
    }
}

struct StudyPageBlock: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: StudyPageBlockKind
    var text: String
    var richTextData: String
    var detail: String
    var isChecked: Bool
    var isExpanded: Bool
    var indentLevel: Int
    var tableColumns: [String]
    var tableRows: [[String]]

    init(
        id: UUID = UUID(),
        kind: StudyPageBlockKind = .text,
        text: String = "",
        richTextData: String = "",
        detail: String = "",
        isChecked: Bool = false,
        isExpanded: Bool = true,
        indentLevel: Int = 0,
        tableColumns: [String] = [],
        tableRows: [[String]] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.richTextData = richTextData
        self.detail = detail
        self.isChecked = isChecked
        self.isExpanded = isExpanded
        self.indentLevel = indentLevel
        self.tableColumns = tableColumns
        self.tableRows = tableRows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(StudyPageBlockKind.self, forKey: .kind) ?? .text
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        richTextData = try container.decodeIfPresent(String.self, forKey: .richTextData) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        indentLevel = try container.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0
        tableColumns = try container.decodeIfPresent([String].self, forKey: .tableColumns) ?? []
        tableRows = try container.decodeIfPresent([[String]].self, forKey: .tableRows) ?? []
    }

    static func table() -> StudyPageBlock {
        StudyPageBlock(
            kind: .table,
            tableColumns: ["열 1", "열 2"],
            tableRows: [["", ""], ["", ""]]
        )
    }
}

@Model
final class StudyMemo {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = "📄"
    var coverStyle: String = "none"
    var blocksJSON: String = ""
    var richTextData: String = ""
    var plainTextContent: String = ""
    var categoryID: String = ""
    var categoryName: String = ""
    var categoryColor: String = "gray"
    var isPinned: Bool = false
    var needsReview: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 이전 유형별 메모를 블록 페이지로 안전하게 변환하기 위한 호환 필드입니다.
    var typeRawValue: String = ""
    var body: String = ""
    var dictationText: String = ""
    var answerText: String = ""
    var translation: String = ""
    var note: String = ""
    var source: String = ""
    var tags: String = ""

    init(
        id: UUID = UUID(),
        title: String = "",
        icon: String = "📄",
        coverStyle: String = "none",
        blocks: [StudyPageBlock] = [StudyPageBlock()],
        richTextData: String = "",
        plainTextContent: String = "",
        categoryID: String = "",
        categoryName: String = "",
        categoryColor: String = "gray",
        isPinned: Bool = false,
        needsReview: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.coverStyle = coverStyle
        self.richTextData = richTextData
        self.plainTextContent = plainTextContent
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryColor = categoryColor
        self.isPinned = isPinned
        self.needsReview = needsReview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        setBlocks(blocks)
    }

    var blocks: [StudyPageBlock] {
        guard let data = blocksJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StudyPageBlock].self, from: data),
              !decoded.isEmpty else {
            return [StudyPageBlock()]
        }
        return decoded
    }

    func setBlocks(_ blocks: [StudyPageBlock]) {
        let safeBlocks = blocks.isEmpty ? [StudyPageBlock()] : blocks
        guard let data = try? JSONEncoder().encode(safeBlocks),
              let json = String(data: data, encoding: .utf8) else { return }
        blocksJSON = json
    }

    @discardableResult
    func migrateLegacyContentIfNeeded() -> Bool {
        guard blocksJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let migratedBlocks: [StudyPageBlock]
        switch typeRawValue {
        case "lcDictation":
            icon = "🎧"
            migratedBlocks = compactBlocks([
                StudyPageBlock(kind: .callout, text: "외부 강의·영상·음원을 들으며 직접 받아쓴 학습 기록입니다."),
                StudyPageBlock(kind: .heading2, text: "출처"),
                StudyPageBlock(text: source),
                StudyPageBlock(kind: .heading2, text: "내가 받아쓴 문장"),
                StudyPageBlock(kind: .quote, text: dictationText),
                StudyPageBlock(kind: .heading2, text: "정답 문장"),
                StudyPageBlock(kind: .toggle, text: "정답 보기", detail: answerText),
                StudyPageBlock(kind: .heading2, text: "한국어 뜻"),
                StudyPageBlock(text: translation),
                StudyPageBlock(kind: .heading2, text: "틀린 표현과 메모"),
                StudyPageBlock(kind: .callout, text: note)
            ])
        case "grammar":
            icon = "📚"
            migratedBlocks = compactBlocks([
                StudyPageBlock(kind: .heading2, text: "핵심 설명"),
                StudyPageBlock(text: body),
                StudyPageBlock(kind: .heading2, text: "형태 또는 공식"),
                StudyPageBlock(kind: .callout, text: answerText),
                StudyPageBlock(kind: .heading2, text: "영어 예문"),
                StudyPageBlock(kind: .quote, text: dictationText),
                StudyPageBlock(text: translation),
                StudyPageBlock(kind: .heading2, text: "주의점과 암기 메모"),
                StudyPageBlock(kind: .callout, text: note)
            ])
        default:
            icon = "📝"
            migratedBlocks = compactBlocks([
                StudyPageBlock(text: body),
                StudyPageBlock(text: note)
            ])
        }

        setBlocks(migratedBlocks)
        return true
    }

    var searchableText: String {
        ([title, categoryName, tags, plainTextContent] + blocks.map(\.text) + blocks.map(\.detail) + blocks.flatMap(\.tableRows).flatMap { $0 })
            .joined(separator: " ")
    }

    var previewText: String {
        if !plainTextContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainTextContent
        }
        for block in blocks {
            if !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return block.text
            }
            if let cell = block.tableRows.flatMap({ $0 }).first(where: { !$0.isEmpty }) {
                return cell
            }
        }
        return "내용을 입력해 보세요."
    }

    private func compactBlocks(_ blocks: [StudyPageBlock]) -> [StudyPageBlock] {
        let filtered = blocks.filter { block in
            block.kind == .divider || block.kind == .table ||
            !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return filtered.isEmpty ? [StudyPageBlock()] : filtered
    }
}

@Model
final class StudyPageCategory {
    var id: UUID = UUID()
    var name: String = ""
    var colorRawValue: String = "gray"
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        colorRawValue: String = "gray",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorRawValue = colorRawValue
        self.createdAt = createdAt
    }
}
