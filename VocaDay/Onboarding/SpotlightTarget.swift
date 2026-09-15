import Foundation

/// 화면 좌표가 아니라 사용자가 이해하는 기능 단위로 온보딩 대상을 식별합니다.
enum SpotlightTarget: String, CaseIterable, Hashable, Sendable {
    case navigation
    case supportingContent
    case settingsButton
    case editDaysButton
    case createDayButton
    case dayCollection
    case storageSelection
    case wordInput
    case addGuide
    case addHelpButton
    case pendingWords
    case saveWordsButton
    case reviewDay
    case createStudyMemoButton
    case studyMemoCollection
}
