import Foundation

// 수면 업데이트 알림을 탭하면 RootTabView가 홈 탭으로 이동하도록 전달하는 앱 전역 라우팅 상태다.
@MainActor
@Observable
final class SleepUpdateNavigationCenter {
    private(set) var openHomeRequestID: UUID?

    init() {
        ReminderNotificationService.onSleepUpdateTapped = { [weak self] in
            self?.openHomeRequestID = UUID()
        }
    }

    func consumeOpenHomeRequest() {
        openHomeRequestID = nil
    }
}
