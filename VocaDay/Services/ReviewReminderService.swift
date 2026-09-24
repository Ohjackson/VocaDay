import Foundation
import UserNotifications

enum ReviewReminderService {
    static let notificationIdentifier = "reviewReminder"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    /// 알림 예약을 다시 계산합니다. 복습할 단어가 없거나 알림 권한이 없으면 예약하지 않습니다.
    static func refreshReminder(dueWordCount: Int, hour: Int, minute: Int, now: Date = Date()) async {
        cancelReminder()

        guard dueWordCount > 0 else { return }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        guard let fireDate = nextFireDate(hour: hour, minute: minute, from: now) else { return }

        let content = UNMutableNotificationContent()
        content.title = "오늘 복습할 단어 \(dueWordCount)개"
        content.body = "지금 VocaDay를 열어 복습을 마쳐보세요."
        content.sound = .default
        content.badge = NSNumber(value: dueWordCount)

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func nextFireDate(hour: Int, minute: Int, from now: Date) -> Date? {
        let calendar = Calendar.current
        guard let todayAtTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            return nil
        }

        if todayAtTime > now {
            return todayAtTime
        }
        return calendar.date(byAdding: .day, value: 1, to: todayAtTime)
    }
}
