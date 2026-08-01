import Foundation

// rMSSD 급격한 변화 알림을 탭하면(ReminderNotificationService.onRMSSDThresholdTapped 콜백)
// 여기 pendingEvent가 채워지고, RootTabView가 이를 관찰해서 입력 화면을 띄운다 — ToastCenter와
// 같은 자리(Components)·같은 역할(전역 environment 객체)이다.
@Observable
final class RMSSDThresholdAlertCenter {
    struct PendingEvent: Identifiable {
        let id = UUID()
        let direction: RMSSDThresholdDirection
        let rmssdValue: Double
        let occurredAt: Date
    }

    var pendingEvent: PendingEvent?

    init() {
        ReminderNotificationService.onRMSSDThresholdTapped = { [weak self] userInfo in
            guard let directionRaw = userInfo[RMSSDThresholdMonitorService.userInfoDirectionKey] as? String,
                  let direction = RMSSDThresholdDirection(rawValue: directionRaw),
                  let value = userInfo[RMSSDThresholdMonitorService.userInfoValueKey] as? Double,
                  let occurredAtRaw = userInfo[RMSSDThresholdMonitorService.userInfoOccurredAtKey] as? String,
                  let occurredAt = DateKey.parseISODate(occurredAtRaw) else { return }
            Task { @MainActor in
                self?.pendingEvent = PendingEvent(direction: direction, rmssdValue: value, occurredAt: occurredAt)
            }
        }
    }
}
