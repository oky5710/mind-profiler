import Foundation
import HealthKit
import UserNotifications

// SDNN 측정이 들어올 때마다 rMSSD를 다시 계산해서 최근 30일 중앙값과 비교하고, 급격히 낮아지거나
// 높아졌으면(RMSSDThreshold) 로컬 알림을 보낸다. HKObserverQuery를 계속 들고 있어야 해서(참조가
// 사라지면 관찰이 끊긴다) enum이 아니라 class다.
@MainActor
final class RMSSDThresholdMonitorService {
    static let shared = RMSSDThresholdMonitorService()

    nonisolated static let categoryIdentifier = "RMSSD_THRESHOLD"
    nonisolated static let userInfoDirectionKey = "rmssdDirection"
    nonisolated static let userInfoValueKey = "rmssdValue"
    nonisolated static let userInfoOccurredAtKey = "rmssdOccurredAt"

    private var observerQuery: HKObserverQuery?
    private var hasStarted = false

    private init() {}

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        do {
            try await HealthKitService.requestAuthorization()
            try await HealthKitService.enableBackgroundDeliveryForSDNNUpdates()
            observerQuery = HealthKitService.observeSDNNUpdates { [weak self] in
                await self?.handleUpdate()
            }
        } catch {
            // 다음 앱 실행(AppDelegate)에서 다시 시도한다 — HealthKit 권한이 아직 없거나 이 기기가
            // 건강 데이터를 지원하지 않는 경우 등, 앱의 다른 기능은 이 실패와 무관하게 정상 동작해야
            // 한다.
            hasStarted = false
        }
    }

    private func handleUpdate() async {
        do {
            let now = Date()
            // 최근 6시간 — "오늘의 패턴" 시간별 모드의 gap 기준(3시간)보다 넉넉하게 잡아서, 알림을
            // 놓치지 않고 최신 샘플을 확실히 잡는다.
            let recent = try await HealthKitService.fetchRMSSDSamples(start: now.addingTimeInterval(-6 * 60 * 60), end: now)
            guard let latest = recent.max(by: { $0.date < $1.date }) else { return }
            guard let median = try await RMSSDThreshold.fetchRecentThirtyDayMedian(asOf: now) else { return }
            guard let direction = RMSSDThreshold.direction(value: latest.value, median: median) else { return }

            // 같은 방향으로 하루에 한 번만 알린다 — 낮은/높은 상태가 몇 시간 이어지는 동안 측정마다
            // 매번 울리면 스팸이 된다.
            let dedupKey = "rmssdThresholdNotified.\(direction.rawValue).\(DateKey.string(from: now))"
            guard UserDefaults.standard.string(forKey: dedupKey) == nil else { return }

            await postNotification(direction: direction, value: latest.value, occurredAt: latest.date)
            UserDefaults.standard.set(DateKey.isoString(from: now), forKey: dedupKey)
        } catch {
            // best-effort — 다음 업데이트나 앱 재실행 때 다시 시도된다.
        }
    }

    private func postNotification(direction: RMSSDThresholdDirection, value: Double, occurredAt: Date) async {
        let content = UNMutableNotificationContent()
        content.title = direction == .low ? "rMSSD가 급격히 낮아졌어요" : "rMSSD가 평소보다 크게 높아졌어요"
        content.body = "지금 기분을 기록해보세요."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.userInfoDirectionKey: direction.rawValue,
            Self.userInfoValueKey: value,
            Self.userInfoOccurredAtKey: DateKey.isoString(from: occurredAt),
        ]
        let request = UNNotificationRequest(
            identifier: "rmssdthreshold.\(direction.rawValue).\(DateKey.string(from: occurredAt))",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
