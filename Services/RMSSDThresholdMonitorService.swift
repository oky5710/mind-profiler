import Foundation
import HealthKit
import UserNotifications

// SDNN 측정이 들어올 때마다 rMSSD를 다시 계산해서 최근 30일의 해당 시간대 중앙값과 비교하고, 급격히 낮아지거나
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
            // 이 화면은 메뉴로 진입하는 경로가 없어서, 알림 권한을 "알림 설정" 화면에 기대면 그
            // 화면을 한 번도 안 연 사용자는 권한이 계속 미결정 상태로 남아 알림이 조용히 안 뜬다 —
            // 여기서 직접 요청한다(이미 허용/거부됐으면 시스템이 그냥 그 상태를 반환한다).
            try await ReminderNotificationService.shared.requestAuthorization()
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

    #if DEBUG
    // 실제 rMSSD를 마음대로 낮추거나 높일 수 없어서, 감지 로직(HealthKit 관찰)은 건너뛰고 "알림이
    // 뜬 이후" 흐름(탭 → 입력 화면 → 저장)만 확인할 수 있게 하는 디버그 전용 트리거.
    func debugTriggerNotification(direction: RMSSDThresholdDirection) async {
        let fakeValue = direction == .low ? 20.0 : 120.0
        await postNotification(direction: direction, value: fakeValue, occurredAt: Date())
    }
    #endif

    private func handleUpdate() async {
        // 설정에서 이 알림을 꺼둔 사용자에게는 실제 발생 감지 자체를 건너뛴다 — 디버그 트리거
        // 버튼은 postNotification을 직접 부르므로 이 설정과 무관하게 항상 테스트할 수 있다.
        guard NotificationPreferences.isRMSSDThresholdAlertEnabled else { return }
        do {
            let now = Date()
            let startOfToday = Calendar.current.startOfDay(for: now)
            // HealthKit 백그라운드 전달은 여러 SDNN 업데이트를 하나의 콜백으로 합쳐서 늦게 깨울 수
            // 있다. 가장 최신 샘플 하나만 보면 먼저 임계값을 넘은 측정을 건너뛰고 두 번째 측정
            // 시각으로 알림이 만들어지므로, 오늘 샘플을 시간순으로 전부 확인한다.
            let todaysSamples = try await HealthKitService.fetchRMSSDSamples(start: startOfToday, end: now)
                .sorted { $0.date < $1.date }
            guard !todaysSamples.isEmpty else { return }
            let baseline = try await RMSSDThreshold.fetchRecentThirtyDayBaseline(asOf: now)

            let occurrenceStoreKey = "rmssdThresholdNotifiedOccurrences.\(DateKey.string(from: now))"
            var notifiedOccurrences = Set(UserDefaults.standard.stringArray(forKey: occurrenceStoreKey) ?? [])

            for sample in todaysSamples {
                guard let median = RMSSDThreshold.periodMedian(at: sample.date, baseline: baseline) else { continue }
                guard let direction = RMSSDThreshold.direction(value: sample.value, median: median) else { continue }

                // observer 콜백은 오늘의 기존 샘플을 다시 포함할 수 있다. 하루 전체를 방향별로 한 번만
                // 막지 않고, 실제 측정 시각+방향이 같은 동일 발생분만 중복 제거한다.
                let occurrenceKey = "\(direction.rawValue).\(DateKey.isoString(from: sample.date))"
                guard !notifiedOccurrences.contains(occurrenceKey) else { continue }

                guard await postNotification(direction: direction, value: sample.value, occurredAt: sample.date) else {
                    continue
                }
                notifiedOccurrences.insert(occurrenceKey)
                UserDefaults.standard.set(Array(notifiedOccurrences), forKey: occurrenceStoreKey)
            }
        } catch {
            // best-effort — 다음 업데이트나 앱 재실행 때 다시 시도된다.
        }
    }

    @discardableResult
    private func postNotification(direction: RMSSDThresholdDirection, value: Double, occurredAt: Date) async -> Bool {
        // 알림 권한을 거부한 상태면 add(request)는 에러 없이 그냥 받아주기만 하고 실제로는 아무것도
        // 안 뜬다 — 그런데도 성공으로 치면, 나중에 사용자가 설정에서 권한을 다시 켜도 이미 오늘 자로
        // "알렸다"고 기록돼 있어 재시도가 안 된다. 실제로 표시될 수 있는 상태인지 먼저 확인한다.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = direction == .low ? "HRV가 급격히 낮아졌어요" : "HRV가 평소보다 크게 높아졌어요"
        content.body = "지금 기분을 기록해보세요."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.userInfoDirectionKey: direction.rawValue,
            Self.userInfoValueKey: value,
            Self.userInfoOccurredAtKey: DateKey.isoString(from: occurredAt),
        ]
        let request = UNNotificationRequest(
            identifier: "rmssdthreshold.\(direction.rawValue).\(Int(occurredAt.timeIntervalSince1970 * 1_000))",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }
}
