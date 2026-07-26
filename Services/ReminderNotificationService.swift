import Foundation
import UserNotifications

// 다른 Service들과 달리 enum 네임스페이스가 아니라 class다 — UNUserNotificationCenterDelegate로
// 동작하려면 참조 타입(식별자를 가진 인스턴스)이 필요하고, 이번에 예약한 알림 목록을 잠깐 캐시해 둬야
// "방금 이 시간대가 체크됐으니 오늘 자 알림만 바로 취소" 같은 즉시 반응이 가능하다.
@MainActor
final class ReminderNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationService()

    static let categoryIdentifier = "MEDICATION_REMINDER"
    static let confirmActionIdentifier = "CONFIRM_ACTION"
    static let cancelActionIdentifier = "CANCEL_ACTION"
    private static let identifierPrefix = "medreminder."
    // 매번 전체를 새로 예약하기엔 너무 머니, 앞으로 이만큼만 미리 채워둔다 — resync가 앱 실행/화면
    // 진입/입력 변경마다 불리므로 이 창이 계속 앞으로 밀리면서 갱신된다.
    private static let scheduleWindowDays = 14

    private var cachedReminders: [MedicationReminderEntry] = []

    private override init() {
        super.init()
    }

    func registerCategories() {
        let confirm = UNNotificationAction(identifier: Self.confirmActionIdentifier, title: "확인", options: [])
        let cancel = UNNotificationAction(identifier: Self.cancelActionIdentifier, title: "취소", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [confirm, cancel],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() async throws {
        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    // 서버의 알림 설정 목록 + 오늘 복용 기록을 다시 읽어와, 우리가 예약해 둔 로컬 알림을 전부
    // 지우고 새로 그린다 — 부분적으로 고쳐 쓰는 것보다 "지우고 다시 그리기"가 드리프트(서버 상태와
    // 로컬 예약이 어긋나는 것) 버그가 없다. HealthKit/EventKit과 같은 원칙으로 실패해도 조용히
    // 넘어간다(알림 기능 하나 때문에 다른 화면까지 에러로 막지 않는다).
    func resync() async {
        do {
            let reminders = try await MedicationReminderService.allReminders()
            cachedReminders = reminders

            let todaysLogs = try await MedicationService.logs(on: Date())
            let takenTodayTimings = Set(todaysLogs.filter(\.taken).compactMap(\.timing))

            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let ourIdentifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ourIdentifiers)

            for reminder in reminders {
                for request in occurrenceRequests(for: reminder, alreadyTakenTodayTimings: takenTodayTimings) {
                    try? await center.add(request)
                }
            }
        } catch {
            // best-effort
        }
    }

    // 특정 시간대가 방금 복용 처리됐을 때, 다음 정기 resync를 기다리지 않고 오늘 자로 남아있는 그
    // 시간대 알림만 즉시 취소한다.
    func cancelTodayOccurrences(forTiming timing: MedicationTiming) {
        let matching = cachedReminders.filter { $0.timing == timing.rawValue }
        guard !matching.isEmpty else { return }
        let todayKey = DateKey.string(from: Date())
        let identifiers = matching.map { "\(Self.identifierPrefix)\($0.id).\(todayKey)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func occurrenceRequests(for reminder: MedicationReminderEntry, alreadyTakenTodayTimings: Set<String>) -> [UNNotificationRequest] {
        guard reminder.isEnabled else { return [] }
        let calendar = Calendar.current
        guard let timeComponents = Self.parseTime(reminder.time),
              let startDate = DateKey.parseISODate(reminder.startDate) else { return [] }
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = reminder.endDate.flatMap(DateKey.parseISODate).map { calendar.startOfDay(for: $0) }
        let today = calendar.startOfDay(for: Date())
        let timingLabel = MedicationTiming(rawValue: reminder.timing)?.label ?? reminder.timing

        var requests: [UNNotificationRequest] = []
        for offset in 0..<Self.scheduleWindowDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard day >= startDay else { continue }
            if let endDay, day > endDay { continue }

            if reminder.repeatType == ReminderRepeatType.weekly.rawValue {
                let weekday = calendar.component(.weekday, from: day)
                guard reminder.weekdays.contains(weekday) else { continue }
            }

            // 오늘 자 발생분인데 이미 그 시간대 복용이 체크돼 있으면 굳이 예약하지 않는다.
            if offset == 0, alreadyTakenTodayTimings.contains(reminder.timing) { continue }

            guard let fireDate = calendar.date(
                bySettingHour: timeComponents.hour,
                minute: timeComponents.minute,
                second: 0,
                of: day
            ), fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "약 복용 알림"
            content.body = "\(timingLabel) 복용할 시간이에요."
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["timing": reminder.timing]

            let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let identifier = "\(Self.identifierPrefix)\(reminder.id).\(DateKey.string(from: day))"
            requests.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return requests
    }

    private static func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }

    // MARK: - UNUserNotificationCenterDelegate

    // 포그라운드 방어선: 예약 이후 다른 경로(예: 홈 퀵버튼)로 이미 그 시간대가 체크됐다면, 큐에
    // 아직 남아있던 알림이라도 화면에 띄우지는 않는다.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            guard let timingRaw = notification.request.content.userInfo["timing"] as? String,
                  let timing = MedicationTiming(rawValue: timingRaw) else {
                completionHandler([.banner, .sound])
                return
            }
            let logs = try? await MedicationService.logs(on: Date())
            let alreadyTaken = logs?.contains { $0.timing == timing.rawValue && $0.taken } ?? false
            completionHandler(alreadyTaken ? [] : [.banner, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == Self.confirmActionIdentifier,
              let timingRaw = response.notification.request.content.userInfo["timing"] as? String,
              let timing = MedicationTiming(rawValue: timingRaw) else {
            completionHandler()
            return
        }
        Task { @MainActor in
            try? await MedicationService.logTiming(timing, date: Date())
            ReminderNotificationService.shared.cancelTodayOccurrences(forTiming: timing)
            completionHandler()
        }
    }
}
