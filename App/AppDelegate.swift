import UIKit
import UserNotifications

// 순수 SwiftUI 라이프사이클(App.init())에서 UNUserNotificationCenter.delegate를 설정하면, 앱이
// 완전히 종료된 상태에서 알림의 액션 버튼을 눌러 앱이 다시 실행되는 launch 경로에서 그 설정이 너무
// 늦게 적용될 수 있다 — didFinishLaunchingWithOptions가 애플이 문서화한 확실한 시점이라 이것만을
// 위해 AppDelegate를 추가한다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = ReminderNotificationService.shared
        ReminderNotificationService.shared.registerCategories()
        // 이 시점에만 등록한다(뷰의 .task 등에서 또 부르지 않음) — 여기가 백그라운드로 깨어난
        // 실행 경로를 포함해 유일하게 보장되는 시점이라, 중복 등록 걱정 없이 한 번만 실행된다.
        Task {
            await RMSSDThresholdMonitorService.shared.start()
            await SleepUpdateMonitorService.shared.start()
        }
        return true
    }
}
