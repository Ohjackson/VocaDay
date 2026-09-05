import Foundation

enum SpotlightDescriptionPlacement: String, Sendable {
    case top
    case center
    case bottom
}

enum SpotlightStep: Int, CaseIterable, Identifiable, Sendable {
    case browseDays
    case createDay
    case editDays
    case openSettings
    case selectStorage
    case enterWord
    case checkPendingWords
    case saveWords
    case openAddHelp
    case review
    case editReview
    case browseStudyMemos
    case studyMemo

    var id: Int { rawValue }

    var target: SpotlightTarget {
        switch self {
        case .browseDays: .dayCollection
        case .createDay: .createDayButton
        case .editDays: .editDaysButton
        case .openSettings: .settingsButton
        case .selectStorage: .storageSelection
        case .enterWord: .wordInput
        case .checkPendingWords: .pendingWords
        case .saveWords: .saveWordsButton
        case .openAddHelp: .addHelpButton
        case .review: .reviewDay
        case .editReview: .editReviewButton
        case .browseStudyMemos: .studyMemoCollection
        case .studyMemo: .createStudyMemoButton
        }
    }

    var title: String {
        switch self {
        case .browseDays: "데이에서 학습 묶음을 확인하세요"
        case .createDay: "첫 데이를 만들어 보세요"
        case .editDays: "데이 이름을 바꾸거나 삭제할 수 있어요"
        case .openSettings: "설정과 백업은 여기에서 관리하세요"
        case .selectStorage: "단어를 저장할 데이를 선택하세요"
        case .enterWord: "학습할 영단어를 입력하세요"
        case .checkPendingWords: "저장 전에 내용을 확인하세요"
        case .saveWords: "확인한 단어를 데이에 저장하세요"
        case .openAddHelp: "JSON 가져오기는 도움말에서 확인하세요"
        case .review: "저장한 단어를 복습하세요"
        case .editReview: "필요 없는 복습 데이를 정리할 수 있어요"
        case .browseStudyMemos: "학습 페이지를 다시 열어 보세요"
        case .studyMemo: "배운 내용을 학습 메모로 정리하세요"
        }
    }

    var message: String {
        switch self {
        case .browseDays:
            "데이는 단어를 날짜나 주제별로 묶는 공간입니다. 카드를 누르면 저장한 단어와 예문을 확인할 수 있어요."
        case .createDay:
            "오른쪽 위 +를 누르면 새 데이가 만들어집니다. 날짜나 주제별로 단어를 나누어 관리할 수 있어요."
        case .editDays:
            "편집 버튼을 누르면 데이 이름 변경과 삭제 버튼이 나타납니다. 삭제한 데이와 단어는 복구할 수 없어요."
        case .openSettings:
            "설정에서는 iCloud 동기화 상태, JSON 파일 백업·복원, 개인정보 및 서비스 안내를 확인할 수 있어요."
        case .selectStorage:
            "저장 위치에서 기존 데이를 고르거나 +로 새 데이를 만드세요. 새로 만든 데이는 자동으로 선택됩니다."
        case .enterWord:
            "영단어나 구문을 입력하고 Enter 또는 키보드의 완료를 누르세요. 한국어 뜻을 확인할 수 있는 저장 전 목록에 담깁니다."
        case .checkPendingWords:
            "영단어와 뜻은 바로 수정할 수 있습니다. ‘예문 · 메모 · 태그’를 열어 세부 내용을 확인하고 휴지통으로 제외하세요."
        case .saveWords:
            "뜻과 예문을 확인한 다음 아래 저장 버튼을 누르세요. 지금은 안내 화면이라 실제 데이터는 저장되지 않습니다."
        case .openAddHelp:
            "? 도움말에는 외부 AI에서 JSON을 만드는 방법과 복사 가능한 프롬프트 예시가 있습니다. VocaDay 안에는 AI가 내장되어 있지 않아요."
        case .review:
            "복습할 데이를 열면 뜻을 가린 채 기억을 확인할 수 있어요. 기억나지 않는 단어는 다시 학습할 단어로 표시하세요."
        case .editReview:
            "편집 버튼을 누르면 복습 목록에서 데이를 삭제할 수 있습니다. 같은 데이가 단어 목록에서도 함께 삭제되니 신중하게 진행하세요."
        case .browseStudyMemos:
            "페이지를 누르면 받아쓰기, 문법, 표현 기록을 이어서 편집할 수 있습니다. 제목과 내용은 입력 즉시 저장돼요."
        case .studyMemo:
            "오른쪽 위 +를 눌러 받아쓰기, 문법, 표현을 자유로운 페이지로 정리할 수 있어요."
        }
    }

    var placement: SpotlightDescriptionPlacement {
        switch self {
        case .saveWords, .checkPendingWords: .top
        case .browseDays, .createDay, .editDays, .openSettings, .selectStorage,
             .enterWord, .openAddHelp, .review, .editReview, .browseStudyMemos, .studyMemo:
            .bottom
        }
    }

    var section: AppSection {
        switch self {
        case .browseDays, .createDay, .editDays, .openSettings: .days
        case .selectStorage, .enterWord, .checkPendingWords, .saveWords, .openAddHelp: .add
        case .review, .editReview: .review
        case .browseStudyMemos, .studyMemo: .studyMemos
        }
    }

    var snapshotValue: String {
        "\(rawValue + 1)|\(target.rawValue)|\(placement.rawValue)|\(section.title)|\(title)|\(message)"
    }
}
