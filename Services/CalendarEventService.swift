import EventKit
import Foundation

enum CalendarEventServiceError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "캘린더 접근 권한이 없어 일정을 불러올 수 없어요."
    }
}

nonisolated enum CalendarEventCategory: Equatable {
    case holiday
    case vacation
    case general
}

enum CalendarEventService {
    typealias Event = (title: String, start: Date, end: Date, isAllDay: Bool, location: String?, category: CalendarEventCategory)

    // EKEventStore는 어느 스레드에서든 안전하게 호출할 수 있고(Apple 문서), fetchEvents가 이
    // store를 detached task(메인 액터 밖)에서 쓰는 게 의도된 설계다.
    nonisolated(unsafe) private static let store = EKEventStore()

    static func requestAuthorization() async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw CalendarEventServiceError.accessDenied
        }
    }

    // HealthKit 쿼리와 달리 EventKit은 조회 기간을 반드시 명시해야 해서(무제한 조회 불가), 인자를
    // 안 넘기면 "오늘의 패턴" 화면이 실제로 스크롤해서 볼 법한 범위보다 넉넉하게 과거 1년~미래
    // 3개월로 고정한다. 보고서처럼 임의의 과거 기간을 분석할 때는 그 기간을 직접 넘겨야, 1년보다
    // 오래된 기간을 분석해도 일정이 조용히 누락되지 않는다.
    static func fetchEvents(start: Date? = nil, end: Date? = nil) async -> [Event] {
        let calendar = Calendar.current
        let rangeStart = start ?? calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let rangeEnd = end ?? calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()

        // events(matching:)는 동기 호출이라 detached task로 넘겨서 메인 액터(호출부인
        // HRVAnalysisViewModel/ReportViewModel)를 막지 않게 한다.
        return await Task.detached(priority: .userInitiated) {
            let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: nil)
            return store.events(matching: predicate).compactMap { event -> Event? in
                let category = category(forCalendarTitle: event.calendar.title)
                // "Holidays in ..." 캘린더에는 실제 쉬는 공휴일뿐 아니라 어버이날처럼 안 쉬는
                // 기념일도 같이 들어 있어서, 실제 관공서 공휴일 이름만 남기고 나머지는 아예 뺀다.
                if category == .holiday && !isLegalHolidayTitle(event.title ?? "") {
                    return nil
                }
                return (
                    title: event.title ?? "제목 없음",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    category: category
                )
            }
        }.value
    }

    // EventKit에는 "공휴일"/"휴가" 같은 일정 유형 개념이 없어서, 애플이 구독 캘린더로 제공하는
    // "Holidays in ..." 캘린더 이름과 사용자가 직접 만든 "휴가" 캘린더 이름으로 구분한다.
    private nonisolated static func category(forCalendarTitle title: String) -> CalendarEventCategory {
        let lowercased = title.lowercased()
        if lowercased.contains("holiday") || title.contains("공휴일") {
            return .holiday
        }
        if lowercased.contains("vacation") || title.contains("휴가") {
            return .vacation
        }
        return .general
    }

    // "관공서의 공휴일에 관한 규정" 기준 법정 공휴일 이름만 화이트리스트로 남긴다 — 어버이날,
    // 스승의날, 국군의날 같은 기념일은 이 목록에 없어서 자동으로 제외된다.
    private nonisolated static let legalHolidayTitleKeywords = [
        "신정", "설날", "삼일절", "어린이날", "부처님", "현충일", "광복절",
        "추석", "개천절", "한글날", "성탄절", "크리스마스", "대체공휴일", "임시공휴일"
    ]

    private nonisolated static func isLegalHolidayTitle(_ title: String) -> Bool {
        legalHolidayTitleKeywords.contains { title.contains($0) }
    }
}
