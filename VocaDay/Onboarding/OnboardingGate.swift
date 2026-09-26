import Foundation

/// 온보딩이 어떻게 끝났는지.
enum OnboardingExit: Equatable {
    /// 마지막 단계의 주 버튼으로 끝냄.
    case finished(SpotlightTour)
    case skipped
}

/// 첫 실행 안내를 띄울지 정한다. 화면·저장소와 분리해 테스트한다.
enum OnboardingGate {
    enum Decision: Equatable {
        case present
        /// 띄우지 않고 완료로 기록한다. `reason` 은 디버그 감독용 설명이다.
        case skip(reason: String)
    }

    /// - Parameters:
    ///   - cloudCompleted: 다른 기기에서 안내를 끝낸 기록이 iCloud에 있는지.
    ///   - hasExistingData: 이미 데이가 있는지 (iCloud 동기화로 들어온 기존 사용자).
    ///   - isSupervisedReplay: 설정 디버그 메뉴에서 일부러 다시 띄운 경우. 이때는 항상 보여 준다.
    static func decide(cloudCompleted: Bool, hasExistingData: Bool, isSupervisedReplay: Bool) -> Decision {
        if isSupervisedReplay { return .present }
        if cloudCompleted { return .skip(reason: "iCloud에 완료 기록이 있어 안내를 건너뛰었어요.") }
        if hasExistingData { return .skip(reason: "이미 데이가 있는 사용자라 안내를 건너뛰었어요.") }
        return .present
    }
}

/// 안내가 끝난 뒤 실제 앱에서 처음 보여 줄 곳.
struct OnboardingLanding: Equatable {
    /// 같은 도착지라도 새로 도착할 때마다 다르다. 화면이 도착을 알아채는 데 쓴다.
    var id = UUID()
    var section: AppSection
    var route: AppRoute?
    /// 디버그 빌드에서 도착 직후 잠깐 보여 주는 감독용 설명.
    var note: String

    static let appDefault = OnboardingLanding(section: .days, route: nil, note: "")

    /// 첫 실행 안내를 끝내면 바로 오늘의 새 단어 검수로 이어 준다. 오늘 이미 만들었으면 학습 탭으로 보낸다.
    /// 건너뛰면 데이 탭(오늘의 새 단어 배너가 있는 곳)에 둔다.
    static func after(_ exit: OnboardingExit, hasAddedToday: Bool) -> OnboardingLanding {
        switch exit {
        case .finished(.core):
            if hasAddedToday {
                return OnboardingLanding(
                    section: .exam,
                    route: nil,
                    note: "완료 → 오늘 단어장을 이미 만들어 학습 탭으로 이동했어요."
                )
            }
            return OnboardingLanding(
                section: .days,
                route: .bundledDayReview,
                note: "완료 → 데이 탭에서 오늘의 새 단어 검수를 열었어요."
            )
        case .finished(.full):
            return OnboardingLanding(section: .days, route: nil, note: "전체 절차 완료 → 데이 탭으로 이동했어요.")
        case .skipped:
            return OnboardingLanding(section: .days, route: nil, note: "건너뛰기 → 데이 탭으로 이동했어요.")
        }
    }
}
