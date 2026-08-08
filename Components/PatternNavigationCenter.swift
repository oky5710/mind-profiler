import Foundation

// 홈 화면의 "전날 수면시간" 카드를 탭하면 오늘의 패턴 탭의 수면 섹션에서 해당 날짜가 바로 보이도록
// 전달하는 앱 전역 라우팅 상태다 — SleepUpdateNavigationCenter와 같은 요청-ID 패턴을 쓴다.
@MainActor
@Observable
final class PatternNavigationCenter {
    private(set) var requestedSleepDate: Date?
    private(set) var openSleepRequestID: UUID?
    private(set) var openHRVTrendRequestID: UUID?

    func requestSleepView(for date: Date) {
        requestedSleepDate = date
        openSleepRequestID = UUID()
    }

    // "최근 HRV" 카드 탭 — 항상 HRV Trend를 시간별 모드로 보여준다.
    func requestHRVTrendView() {
        openHRVTrendRequestID = UUID()
    }

    func consumeOpenSleepRequest() {
        openSleepRequestID = nil
    }

    func consumeOpenHRVTrendRequest() {
        openHRVTrendRequestID = nil
    }
}
