import EventKit
import Foundation

enum CalendarEventServiceError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "캘린더 접근 권한이 없어 일정을 불러올 수 없어요."
    }
}

enum CalendarEventService {
    private static let store = EKEventStore()

    static func requestAuthorization() async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw CalendarEventServiceError.accessDenied
        }
    }

    // HealthKit 쿼리와 달리 EventKit은 조회 기간을 반드시 명시해야 해서(무제한 조회 불가),
    // 차트가 실제로 스크롤해서 볼 법한 범위보다 넉넉하게 과거 1년~미래 3개월로 고정한다.
    static func fetchEvents() async -> [(title: String, start: Date, end: Date, isAllDay: Bool, location: String?)] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()

        // events(matching:)는 동기 호출이라 detached task로 넘겨서 메인 액터(호출부인
        // HRVAnalysisViewModel)를 막지 않게 한다.
        return await Task.detached(priority: .userInitiated) {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).map { event in
                (
                    title: event.title ?? "제목 없음",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location
                )
            }
        }.value
    }
}
