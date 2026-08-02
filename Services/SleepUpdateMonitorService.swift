import Foundation
import HealthKit
import UserNotifications

// HealthKit 수면 데이터 변경을 백그라운드에서 관찰하고, 새 "밤"이 처음 확인됐을 때 한 번만
// 로컬 알림을 보낸다. 수면 단계 샘플이 여러 건 들어오므로 종료 시각이 아니라 nightLabel을 중복 키로 쓴다.
@MainActor
final class SleepUpdateMonitorService {
    static let shared = SleepUpdateMonitorService()

    nonisolated static let categoryIdentifier = "SLEEP_DATA_UPDATED"

    private static let latestObservedNightKey = "sleepUpdate.latestObservedNight"
    private static let lookupDayCount = 3

    private var observerQuery: HKObserverQuery?
    private var hasStarted = false

    private init() {}

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try await HealthKitService.requestAuthorization()
            try await ReminderNotificationService.shared.requestAuthorization()

            // 최초 설치·기능 추가 직후에는 이미 존재하던 수면으로 알림을 보내지 않고 기준만 저장한다.
            if UserDefaults.standard.string(forKey: Self.latestObservedNightKey) == nil {
                await establishInitialBaseline()
            }

            try await HealthKitService.enableBackgroundDeliveryForSleepUpdates()
            observerQuery = HealthKitService.observeSleepUpdates { [weak self] in
                await self?.handleUpdate()
            }
        } catch {
            // 권한이나 HealthKit 사용 가능 여부가 바뀔 수 있으므로 다음 앱 실행에서 다시 시도한다.
            hasStarted = false
        }
    }

    private func establishInitialBaseline() async {
        guard let latestNight = try? await fetchLatestNight() else { return }
        UserDefaults.standard.set(DateKey.string(from: latestNight), forKey: Self.latestObservedNightKey)
    }

    private func handleUpdate() async {
        guard let latestNight = try? await fetchLatestNight() else { return }
        let nightKey = DateKey.string(from: latestNight)
        let previousKey = UserDefaults.standard.string(forKey: Self.latestObservedNightKey)
        guard nightKey != previousKey else { return }

        guard await postNotification(for: latestNight) else { return }
        UserDefaults.standard.set(nightKey, forKey: Self.latestObservedNightKey)
    }

    private func fetchLatestNight() async throws -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -Self.lookupDayCount, to: now) ?? now
        let samples = try await HealthKitService.fetchSleepStageSamples(start: start, end: now)
        return samples.map { SleepAnalysisService.nightLabel(for: $0.start) }.max()
    }

    private func postNotification(for night: Date) async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral else { return false }

        let content = UNMutableNotificationContent()
        content.title = "새로운 수면 데이터가 동기화됐어요"
        content.body = "오늘의 수사 노트를 확인해 보세요."
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier

        let request = UNNotificationRequest(
            identifier: "sleepupdate.\(DateKey.string(from: night))",
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
