import Foundation
import Combine

protocol OnboardingCompletionStoring: AnyObject {
    func isCompleted(forKey key: String) -> Bool
    func setCompleted(_ completed: Bool, forKey key: String)
}

final class UserDefaultsOnboardingCompletionStore: OnboardingCompletionStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isCompleted(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    func setCompleted(_ completed: Bool, forKey key: String) {
        defaults.set(completed, forKey: key)
    }
}

/// 완료 기록을 이 기기(UserDefaults)와 iCloud 키-값 저장소에 함께 남긴다.
/// 어느 한쪽에라도 완료 기록이 있으면 완료로 본다. 새 기기·재설치에서 투어를 다시 띄우지 않기 위해서다.
final class UbiquitousOnboardingCompletionStore: OnboardingCompletionStoring {
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.cloud = cloud
    }

    func isCompleted(forKey key: String) -> Bool {
        defaults.bool(forKey: key) || cloud.bool(forKey: key)
    }

    func setCompleted(_ completed: Bool, forKey key: String) {
        defaults.set(completed, forKey: key)
        cloud.set(completed, forKey: key)
        cloud.synchronize()
    }
}

enum SpotlightOnboardingCompletion {
    nonisolated static let version = 3
    nonisolated static let versionedKey = "hasCompletedComponentSpotlightOnboarding_v\(version)"
}

/// 다음에 온보딩을 띄울 때 쓸 절차와 시작 단계. 설정의 디버그 메뉴가 남기고, 한 번 쓰면 지운다.
enum SpotlightTourRequest {
    private static let tourKey = "spotlightRequestedTour"
    private static let stepKey = "spotlightRequestedStep"

    static func request(_ tour: SpotlightTour, startingAt step: SpotlightStep? = nil, defaults: UserDefaults = .standard) {
        defaults.set(tour.rawValue, forKey: tourKey)
        if let step {
            defaults.set(step.rawValue, forKey: stepKey)
        } else {
            defaults.removeObject(forKey: stepKey)
        }
    }

    static func hasPending(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: tourKey) != nil
    }

    static func consume(defaults: UserDefaults = .standard) -> (tour: SpotlightTour, step: SpotlightStep?) {
        let tour = defaults.string(forKey: tourKey).flatMap(SpotlightTour.init(rawValue:)) ?? .core
        let step = defaults.object(forKey: stepKey) == nil ? nil : SpotlightStep(rawValue: defaults.integer(forKey: stepKey))
        defaults.removeObject(forKey: tourKey)
        defaults.removeObject(forKey: stepKey)
        return (tour, step)
    }
}

@MainActor
final class SpotlightFlowController: ObservableObject {
    @Published private(set) var currentStep: SpotlightStep
    @Published private(set) var tour: SpotlightTour

    private let completionStore: OnboardingCompletionStoring
    private let completionKey: String

    init(
        initialStep: SpotlightStep,
        tour: SpotlightTour = .core,
        completionStore: OnboardingCompletionStoring,
        completionKey: String = SpotlightOnboardingCompletion.versionedKey
    ) {
        // 절차에 없는 단계를 받으면 그 단계가 있는 전체 절차로 보여 준다.
        self.tour = tour.steps.contains(initialStep) ? tour : .full
        currentStep = initialStep
        self.completionStore = completionStore
        self.completionKey = completionKey
    }

    convenience init(initialStep: SpotlightStep = SpotlightTour.core.steps[0]) {
        self.init(
            initialStep: initialStep,
            completionStore: UbiquitousOnboardingCompletionStore(),
            completionKey: SpotlightOnboardingCompletion.versionedKey
        )
    }

    var steps: [SpotlightStep] { tour.steps }
    private var currentIndex: Int { steps.firstIndex(of: currentStep) ?? 0 }
    /// 화면에 보이는 단계 번호 (1부터).
    var stepNumber: Int { currentIndex + 1 }
    var isLastStep: Bool { currentIndex == steps.count - 1 }
    var canGoBack: Bool { currentIndex > 0 }
    var isCompleted: Bool { completionStore.isCompleted(forKey: completionKey) }

    func moveBack() {
        guard canGoBack else { return }
        currentStep = steps[currentIndex - 1]
    }

    func moveNext() {
        guard !isLastStep else {
            finish()
            return
        }
        currentStep = steps[currentIndex + 1]
    }

    func skip() {
        finish()
    }

    func finish() {
        completionStore.setCompleted(true, forKey: completionKey)
    }

    func restart() {
        completionStore.setCompleted(false, forKey: completionKey)
        tour = .core
        currentStep = tour.steps[0]
    }

    /// 온보딩을 다시 띄우기 직전에 부른다. 디버그 메뉴가 요청한 절차·단계가 있으면 그걸로 시작한다.
    func prepareForPresentation() {
        let request = SpotlightTourRequest.consume()
        tour = request.tour
        currentStep = request.step.flatMap { tour.steps.contains($0) ? $0 : nil } ?? tour.steps[0]
    }

    #if DEBUG
    func setStepForVisualVerification(_ step: SpotlightStep) {
        currentStep = step
    }
    #endif
}
