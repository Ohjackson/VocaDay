import Foundation
import UserNotifications

/// 1차 세션에서 틀린 단어가 있으면 6시간 뒤 재도전 알림 (SPEC §2.2, 단고초 scheduleRetryNotification).
/// 하루 1회 복습 알림(`ReviewReminderService`)과 식별자가 달라 서로 덮어쓰지 않는다.
enum ExamRetryReminderService {
    nonisolated static let notificationIdentifier = "examRetryReminder"

    static func schedule(at fireDate: Date, wordCount: Int, now: Date = Date()) async {
        cancel()
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "재도전 학습을 시작할 수 있어요"
        content.body = "틀린 단어 \(wordCount)개를 다시 풀면 오늘 학습이 끝나요."
        content.sound = .default

        let interval = max(fireDate.timeIntervalSince(now), 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    nonisolated static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }
}

/// 시험 설정 키 (SPEC 기본값: 오타 허용 켜짐, near miss 재시도 켜짐, 예문 번역 표시 켜짐, 레슨 15문제).
nonisolated enum ExamSettingsKeys {
    static let allowsTypo = "examAllowsTypo"
    static let allowsNearMissRetry = "examAllowsNearMissRetry"
    /// 빈칸 문제에서 예문 해석을 처음부터 보여 줄지. 기본은 가림 (예전 키와 달리 기본값이 false라 새 키를 쓴다).
    static let showsExampleTranslation = "examShowsExampleTranslationByDefault"
    static let introducesNewWords = "examIntroducesNewWords"

    static func plannerConfig(defaults: UserDefaults = .standard) -> SessionPlannerConfig {
        var config = SessionPlannerConfig.standard
        config.introducesNewWords = defaults.object(forKey: introducesNewWords) as? Bool ?? false
        return config
    }

    static func gradingOptions(defaults: UserDefaults = .standard) -> GradingOptions {
        GradingOptions(
            allowsTypo: defaults.object(forKey: allowsTypo) as? Bool ?? true,
            allowsNearMissRetry: defaults.object(forKey: allowsNearMissRetry) as? Bool ?? true
        )
    }
}
