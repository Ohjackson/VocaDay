import Foundation

enum SpotlightDescriptionPlacement: String, Sendable {
    case top
    case center
    case bottom
}

/// 첫 실행에서는 단어를 저장하고 복습하기까지의 핵심 흐름만 안내합니다.
/// 편집, 설정, JSON, 학습 메모는 각 화면의 도움말에서 필요할 때 확인합니다.
enum SpotlightStep: Int, CaseIterable, Identifiable, Sendable {
    case browseDays
    case enterWord
    case saveWords
    case review

    var id: Int { rawValue }

    var target: SpotlightTarget {
        switch self {
        case .browseDays: .dayCollection
        case .enterWord: .wordInput
        case .saveWords: .saveWordsButton
        case .review: .reviewDay
        }
    }

    var title: String {
        switch self {
        case .browseDays: "단어를 데이별로 모아요"
        case .enterWord: "원하는 방식으로 단어를 추가해요"
        case .saveWords: "확인한 내용만 저장해요"
        case .review: "기억하면서 복습해요"
        }
    }

    var message: String {
        switch self {
        case .browseDays:
            "데이는 단어를 날짜나 주제별로 묶는 공간입니다. 단어 화면에서는 영어를 누르면 발음을 듣고, 번호를 누르면 예문과 메모를 볼 수 있어요."
        case .enterWord:
            "영단어를 입력하고 Enter를 누르면 수동 입력 항목이 생깁니다. 지원 기기에서는 AI로 생성 버튼으로 뜻과 예문을 자동으로 채울 수 있어요."
        case .saveWords:
            "저장 전 목록에서 뜻과 예문을 확인하고 자유롭게 고치세요. 준비가 끝나면 아래 버튼으로 선택한 데이에 저장합니다."
        case .review:
            "뜻 보기를 눌러 답을 확인한 뒤 각 단어를 ‘다시’ 또는 ‘알아요’로 표시하세요. 모든 단어를 판단하면 복습을 완료할 수 있어요."
        }
    }

    var placement: SpotlightDescriptionPlacement {
        switch self {
        case .saveWords: .top
        case .browseDays, .enterWord, .review: .bottom
        }
    }

    var section: AppSection {
        switch self {
        case .browseDays: .days
        case .enterWord, .saveWords: .add
        case .review: .review
        }
    }

    var snapshotValue: String {
        "\(rawValue + 1)|\(target.rawValue)|\(placement.rawValue)|\(section.title)|\(title)|\(message)"
    }
}
