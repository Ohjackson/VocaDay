import Foundation
import SwiftData

enum StudyPageKind: String, CaseIterable, Identifiable {
    case markdown
    case table

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "마크다운 문서"
        case .table: "표"
        }
    }

    var subtitle: String {
        switch self {
        case .markdown: "제목, 목록, 체크리스트를 자유롭게 기록해요."
        case .table: "원하는 열을 만들고 셀을 직접 편집해요."
        }
    }

    var systemImage: String {
        switch self {
        case .markdown: "doc.richtext"
        case .table: "tablecells"
        }
    }
}

enum StudyTableColumnKind: String, Codable, CaseIterable, Identifiable {
    case text
    case number
    case checkbox
    case selection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "텍스트"
        case .number: "숫자"
        case .checkbox: "체크"
        case .selection: "선택"
        }
    }
}

struct StudyTableColumn: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var kind: StudyTableColumnKind = .text
    var isHidden: Bool = false
    var options: [String] = []
}

struct StudyTableRow: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var values: [String: String] = [:]
}

@Model
final class CustomStudyPage {
    var id: UUID = UUID()
    var title: String = ""
    var iconName: String = "doc.richtext"
    var kindRawValue: String = StudyPageKind.markdown.rawValue
    var markdown: String = ""
    var columnsJSON: String = "[]"
    var rowsJSON: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String,
        kind: StudyPageKind,
        markdown: String = "",
        columns: [StudyTableColumn] = [],
        rows: [StudyTableRow] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.kindRawValue = kind.rawValue
        self.markdown = markdown
        self.columnsJSON = Self.encode(columns)
        self.rowsJSON = Self.encode(rows)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: StudyPageKind {
        StudyPageKind(rawValue: kindRawValue) ?? .markdown
    }

    var columns: [StudyTableColumn] {
        get { Self.decode([StudyTableColumn].self, from: columnsJSON) ?? [] }
        set {
            columnsJSON = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    var rows: [StudyTableRow] {
        get { Self.decode([StudyTableRow].self, from: rowsJSON) ?? [] }
        set {
            rowsJSON = Self.encode(newValue)
            updatedAt = Date()
        }
    }

    var summary: String {
        switch kind {
        case .markdown:
            let firstLine = markdown
                .components(separatedBy: .newlines)
                .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return firstLine ?? "아직 내용이 없습니다."
        case .table:
            return "\(rows.count)행 · \(columns.count)열"
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
