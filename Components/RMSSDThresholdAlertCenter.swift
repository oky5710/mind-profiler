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
        ReminderNotificationService.onRMSSDThresholdTapped = { userInfo in
            // userInfo([AnyHashable: Any])는 Sendable이 아니라 Task 클로저로 그대로 넘길 수 없다 —
            // 여기(비격리 컨텍스트)에서 Sendable한 원시값만 먼저 꺼내고, MainActor 격리가 필요한
            // DateKey.parseISODate 호출과 pendingEvent 대입만 Task 안에서 한다.
            guard let directionRaw = userInfo[RMSSDThresholdMonitorService.userInfoDirectionKey] as? String,
                  let direction = RMSSDThresholdDirection(rawValue: directionRaw),
                  let value = userInfo[RMSSDThresholdMonitorService.userInfoValueKey] as? Double,
                  let occurredAtRaw = userInfo[RMSSDThresholdMonitorService.userInfoOccurredAtKey] as? String
            else { return }
            Task { @MainActor [weak self] in
                guard let occurredAt = DateKey.parseISODate(occurredAtRaw) else { return }
                self?.pendingEvent = PendingEvent(direction: direction, rmssdValue: value, occurredAt: occurredAt)
            }
        }
    }
}
