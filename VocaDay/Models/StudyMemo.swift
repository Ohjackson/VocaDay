import Foundation
import SwiftData

enum StudyMemoType: String, CaseIterable, Codable, Identifiable {
    case lcDictation
    case grammar
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lcDictation: "LC 받아쓰기"
        case .grammar: "문법 정리"
        case .general: "자유 메모"
        }
    }

    var shortTitle: String {
        switch self {
        case .lcDictation: "LC"
        case .grammar: "문법"
        case .general: "일반"
        }
    }

    var systemImage: String {
        switch self {
        case .lcDictation: "headphones"
        case .grammar: "text.book.closed"
        case .general: "note.text"
        }
    }

    var description: String {
        switch self {
        case .lcDictation: "외부 음원을 듣고 받아쓴 문장과 정답을 비교합니다."
        case .grammar: "문법의 핵심, 형태, 예문과 주의점을 정리합니다."
        case .general: "형식에 구애받지 않고 학습 내용을 기록합니다."
        }
    }
}

@Model
final class StudyMemo {
    var id: UUID = UUID()
    var typeRawValue: String = StudyMemoType.general.rawValue
    var title: String = ""
    var body: String = ""
    var dictationText: String = ""
    var answerText: String = ""
    var translation: String = ""
    var note: String = ""
    var source: String = ""
    var tags: String = ""
    var isPinned: Bool = false
    var needsReview: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        type: StudyMemoType,
        title: String = "",
        body: String = "",
        dictationText: String = "",
        answerText: String = "",
        translation: String = "",
        note: String = "",
        source: String = "",
        tags: String = "",
        isPinned: Bool = false,
        needsReview: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.title = title
        self.body = body
        self.dictationText = dictationText
        self.answerText = answerText
        self.translation = translation
        self.note = note
        self.source = source
        self.tags = tags
        self.isPinned = isPinned
        self.needsReview = needsReview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: StudyMemoType {
        get { StudyMemoType(rawValue: typeRawValue) ?? .general }
        set { typeRawValue = newValue.rawValue }
    }

    var searchableText: String {
        [title, body, dictationText, answerText, translation, note, source, tags]
            .joined(separator: " ")
    }

    var previewText: String {
        let candidates: [String]
        switch type {
        case .lcDictation:
            candidates = [dictationText, answerText, note]
        case .grammar:
            candidates = [body, answerText, dictationText, note]
        case .general:
            candidates = [body, note]
        }
        return candidates.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "내용을 입력해 보세요."
    }
}
