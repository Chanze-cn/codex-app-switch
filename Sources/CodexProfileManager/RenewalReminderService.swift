import Foundation
import UserNotifications

struct RenewalReminderService {
    func nextRenewalDate(day: Int, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let start = calendar.startOfDay(for: date)
        for offset in 0...2 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(day, range.count)
            components.hour = 9
            if let candidate = calendar.date(from: components), candidate >= start {
                return candidate
            }
        }
        return nil
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func schedule(for profile: CodexProfile) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [7, 3, 1].map { identifier(profile.id, $0) })
        guard let renewalDay = profile.renewalDay,
              let renewalDate = nextRenewalDate(day: renewalDay) else { return }

        for days in profile.reminderDays {
            guard let date = Calendar.current.date(byAdding: .day, value: -days, to: renewalDate),
                  date > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(profile.displayName) 将在 \(days) 天后续费"
            content.body = "请前往 ChatGPT 官方订阅页面检查续费状态。"
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
            try await center.add(.init(
                identifier: identifier(profile.id, days),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    private func identifier(_ id: UUID, _ days: Int) -> String {
        "renewal-\(id.uuidString)-\(days)"
    }
}
