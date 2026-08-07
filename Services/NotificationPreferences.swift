import Foundation

// 알림 종류별 켬/끔 — 기기에만 있으면 되는 설정이라 서버 없이 UserDefaults로 저장한다. 기존
// 사용자가 이미 받고 있던 알림을 설정을 열어보지 않아도 그대로 유지하도록 기본값은 항상 true다.
enum NotificationPreferences {
    private static let rmssdThresholdAlertKey = "notificationPreferences.rmssdThresholdAlertEnabled"
    private static let sleepUpdateAlertKey = "notificationPreferences.sleepUpdateAlertEnabled"

    static var isRMSSDThresholdAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: rmssdThresholdAlertKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: rmssdThresholdAlertKey) }
    }

    static var isSleepUpdateAlertEnabled: Bool {
        get { UserDefaults.standard.object(forKey: sleepUpdateAlertKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: sleepUpdateAlertKey) }
    }
}
