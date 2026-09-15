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

enum SpotlightOnboardingCompletion {
    nonisolated static let version = 3
    nonisolated static let versionedKey = "hasCompletedComponentSpotlightOnboarding_v\(version)"
}

@MainActor
final class SpotlightFlowController: ObservableObject {
    @Published private(set) var currentStep: SpotlightStep

    private let completionStore: OnboardingCompletionStoring
    private let completionKey: String

    init(
        initialStep: SpotlightStep,
        completionStore: OnboardingCompletionStoring,
        completionKey: String = SpotlightOnboardingCompletion.versionedKey
    ) {
        currentStep = initialStep
        self.completionStore = completionStore
        self.completionKey = completionKey
    }

    convenience init(initialStep: SpotlightStep = .browseDays) {
        self.init(
            initialStep: initialStep,
            completionStore: UserDefaultsOnboardingCompletionStore(),
            completionKey: SpotlightOnboardingCompletion.versionedKey
        )
    }

    var canGoBack: Bool { currentStep.rawValue > 0 }
    var isCompleted: Bool { completionStore.isCompleted(forKey: completionKey) }

    func moveBack() {
        guard let previous = SpotlightStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    func moveNext() {
        guard let next = SpotlightStep(rawValue: currentStep.rawValue + 1) else {
            finish()
            return
        }
        currentStep = next
    }

    func skip() {
        finish()
    }

    func finish() {
        completionStore.setCompleted(true, forKey: completionKey)
    }

    func restart() {
        completionStore.setCompleted(false, forKey: completionKey)
        currentStep = .browseDays
    }

    func prepareForPresentation() {
        currentStep = .browseDays
    }

    #if DEBUG
    func setStepForVisualVerification(_ step: SpotlightStep) {
        currentStep = step
    }
    #endif
}
