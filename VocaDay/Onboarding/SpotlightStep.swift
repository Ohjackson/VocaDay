import Foundation

enum SpotlightDescriptionPlacement: String, Sendable {
    case top
    case center
    case bottom
}

/// 안내 절차. 첫 실행은 핵심 3단계(`core`)만, 개발자용 전체 체험은 앱의 모든 안내(`full`)를 보여 준다.
/// 핵심 절차는 기능 목록이 아니라 "매일 20개 → 앱이 복습 날짜를 정함 → 내 단어도 추가" 순서로 쓰는 이유를 보여 준다.
enum SpotlightTour: String, Sendable {
    case core
    case full

    var steps: [SpotlightStep] {
        switch self {
        case .core:
            [.dailyWords, .todayStudy, .enterWord]
        case .full:
            [
                .dailyWords, .browseDays, .createDay, .editDays, .openSettings,
                .todayStudy,
                .selectStorage, .enterWord, .checkPendingWords, .saveWords, .openAddHelp,
                .browseStudyMemos, .createStudyMemo
            ]
        }
    }

    /// 마지막 단계의 주 버튼. 첫 실행은 바로 오늘의 새 단어로 이어진다.
    var finishTitle: String {
        switch self {
        case .core: "오늘의 새 단어 고르기"
        case .full: "완료"
        }
    }
}

/// 온보딩 한 단계. 순서는 `SpotlightTour.steps`가 정하고, rawValue는 식별용이다.
enum SpotlightStep: Int, CaseIterable, Identifiable, Sendable {
    case dailyWords
    case todayStudy
    case enterWord
    // 전체 체험에만 나오는 단계
    case browseDays
    case saveWords
    case createDay
    case editDays
    case openSettings
    case selectStorage
    case checkPendingWords
    case openAddHelp
    case browseStudyMemos
    case createStudyMemo

    var id: Int { rawValue }

    var target: SpotlightTarget {
        switch self {
        case .dailyWords: .todayWordsBanner
        case .todayStudy: .studyStatus
        case .browseDays: .dayCollection
        case .enterWord: .wordInput
        case .saveWords: .saveWordsButton
        case .createDay: .createDayButton
        case .editDays: .editDaysButton
        case .openSettings: .settingsButton
        case .selectStorage: .storageSelection
        case .checkPendingWords: .pendingWords
        case .openAddHelp: .addHelpButton
        case .browseStudyMemos: .studyMemoCollection
        case .createStudyMemo: .createStudyMemoButton
        }
    }

    var title: String {
        switch self {
        case .dailyWords: "매일 새 단어 20개로 시작해요"
        case .todayStudy: "복습 날짜는 앱이 정해요"
        case .enterWord: "내 단어도 넣을 수 있어요"
        case .browseDays: "단어를 데이별로 모아요"
        case .saveWords: "확인한 내용만 저장해요"
        case .createDay: "새 데이를 만들어요"
        case .editDays: "데이 이름을 바꾸거나 지워요"
        case .openSettings: "설정과 백업은 여기에서 관리해요"
        case .selectStorage: "저장할 데이를 골라요"
        case .checkPendingWords: "시험에 필요한 데이터를 확인해요"
        case .openAddHelp: "추가 방법은 도움말에 있어요"
        case .browseStudyMemos: "학습 메모를 다시 열어 봐요"
        case .createStudyMemo: "배운 내용을 메모로 정리해요"
        }
    }

    var message: String {
        switch self {
        case .dailyWords:
            "‘오늘의 새 단어’를 누르면 토익 단어가 한 장씩 나와요. 외울 단어만 골라 담으면 오늘의 데이가 만들어지고, 이미 아는 단어는 보관함으로 빠져요."
        case .todayStudy:
            "학습 탭에는 오늘 풀 단어만 모여요. 맞힌 단어는 점점 긴 간격으로, 틀린 단어는 곧 다시 나와요. 매일 ‘오늘 학습’만 끝내면 돼요."
        case .browseDays:
            "데이는 단어를 날짜나 주제별로 묶는 공간입니다. 단어 화면에서는 영어를 누르면 발음을 듣고, 번호를 누르면 예문과 메모를 볼 수 있어요."
        case .enterWord:
            "추가 탭에서 영단어를 입력하고 뜻과 예문을 채워 원하는 데이에 저장하세요. 저장 전에 목록에서 확인하고 고칠 수 있어요."
        case .saveWords:
            "저장 전 목록에서 뜻과 예문을 확인하고 자유롭게 고치세요. 준비가 끝나면 아래 버튼으로 선택한 데이에 저장합니다."
        case .createDay:
            "‘새 데이’를 누르면 이름을 정해 데이를 만들어요. 매일 새 단어 20개는 데이 목록 위 ‘오늘의 새 단어’에서 골라 데이로 만들 수 있어요."
        case .editDays:
            "편집 버튼을 누르면 데이마다 이름 변경과 삭제 버튼이 나와요. 삭제한 데이의 단어와 학습 기록은 되돌릴 수 없어요."
        case .openSettings:
            "설정에서 iCloud 동기화 상태, 학습 알림, JSON 백업·복원, 개인정보 안내를 확인할 수 있어요."
        case .selectStorage:
            "저장 위치에서 기존 데이를 고르거나 +로 새 데이를 만드세요. 새로 만든 데이는 자동으로 선택돼요."
        case .checkPendingWords:
            "영단어와 뜻은 바로 고칠 수 있어요. 모든 시험 유형이 나오려면 뜻, 단어가 들어간 영어 예문, 예문 번역이 필요해요."
        case .openAddHelp:
            "? 도움말에서 카드·시험에 필요한 단어 데이터와 Apple Intelligence로 단어를 추가하는 방법을 확인할 수 있어요."
        case .browseStudyMemos:
            "페이지를 누르면 받아쓰기, 문법, 표현 기록을 이어서 편집할 수 있어요. 입력하는 즉시 저장돼요."
        case .createStudyMemo:
            "‘새 페이지’를 눌러 받아쓰기, 문법, 표현을 자유로운 페이지로 정리할 수 있어요."
        }
    }

    var placement: SpotlightDescriptionPlacement {
        switch self {
        case .saveWords, .checkPendingWords: .top
        case .dailyWords, .todayStudy, .browseDays, .enterWord, .createDay, .editDays, .openSettings,
             .selectStorage, .openAddHelp, .browseStudyMemos, .createStudyMemo:
            .bottom
        }
    }

    var section: AppSection {
        switch self {
        case .dailyWords, .browseDays, .createDay, .editDays, .openSettings: .days
        case .enterWord, .saveWords, .selectStorage, .checkPendingWords, .openAddHelp: .add
        case .todayStudy: .exam
        case .browseStudyMemos, .createStudyMemo: .studyMemos
        }
    }

    var snapshotValue: String {
        "\(rawValue + 1)|\(target.rawValue)|\(placement.rawValue)|\(section.title)|\(title)|\(message)"
    }
}
