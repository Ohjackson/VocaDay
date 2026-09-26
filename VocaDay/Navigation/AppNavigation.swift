import Foundation

/// 앱 안에서 push 되는 모든 화면의 목록입니다.
///
/// 규칙 (NavigationArchitectureTests 가 검사합니다):
/// - 화면 이동은 `NavigationLink(value: AppRoute.…)` 또는 `\.appNavigate` 로만 합니다.
/// - `NavigationLink { … }`, `NavigationLink(destination:)`, `navigationDestination(item:/isPresented:)` 처럼
///   경로(path) 밖에서 화면을 쌓는 방식은 쓰지 않습니다. 그렇게 쌓인 화면은 섹션을 바꿔도
///   지워지지 않아 macOS 사이드바 선택과 본문이 어긋납니다.
/// - 모델은 ID 로만 넘기고 목적지에서 다시 조회합니다.
enum AppRoute: Hashable {
    case settings
    case settingsBackup
    case settingsPrivacy
    case addWordsHelp
    case bundledDayReview
    case setAsideWords
    case dayWords(dayID: UUID)
    case wordEdit(wordID: UUID)
    case reviewSession(dayID: UUID, dueOnly: Bool)
    case studyMemo(memoID: UUID)
    case wordStudyDetail(wordID: UUID)
    case examSession
}

/// 선택된 섹션과 섹션별 내비게이션 경로를 한곳에서 관리합니다.
///
/// 사이드바/탭 선택과 본문 스택을 같은 값에서 파생시키므로 둘이 어긋날 수 없습니다.
struct AppNavigationState: Equatable {
    /// 섹션을 바꿀 때 기존 스택을 어떻게 처리할지.
    enum SectionChangePolicy {
        /// macOS: 본문 열이 하나뿐이므로 섹션을 바꾸면 모든 스택을 루트로 되돌립니다.
        case resetAllStacks
        /// iOS: 탭마다 스택이 따로 있으므로 탭별 경로를 유지합니다.
        case keepStacks
    }

    private(set) var selectedSection: AppSection
    private var paths: [AppSection: [AppRoute]] = [:]

    init(selectedSection: AppSection = .days) {
        self.selectedSection = selectedSection
    }

    static var platformPolicy: SectionChangePolicy {
        #if os(macOS)
        .resetAllStacks
        #else
        .keepStacks
        #endif
    }

    func path(for section: AppSection) -> [AppRoute] {
        paths[section] ?? []
    }

    mutating func setPath(_ path: [AppRoute], for section: AppSection) {
        paths[section] = path.isEmpty ? nil : path
    }

    mutating func select(_ section: AppSection, policy: SectionChangePolicy = platformPolicy) {
        if policy == .resetAllStacks {
            paths.removeAll()
        }
        selectedSection = section
    }

    mutating func push(_ route: AppRoute) {
        paths[selectedSection, default: []].append(route)
    }

    mutating func replaceTop(with route: AppRoute) {
        var path = paths[selectedSection] ?? []
        if !path.isEmpty {
            path.removeLast()
        }
        path.append(route)
        setPath(path, for: selectedSection)
    }

    mutating func pop() {
        guard var path = paths[selectedSection], !path.isEmpty else { return }
        path.removeLast()
        setPath(path, for: selectedSection)
    }
}
