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
        return true
    }
}
