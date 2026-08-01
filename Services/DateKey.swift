import Foundation

enum DateKey {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) {
            return date
        }
        return ISO8601DateFormatter().date(from: string)
    }

    // 백엔드의 순수 날짜 필드(Prisma `@db.Date` — MoodLog.date, MedicationLog.date 등)는 시각
    // 정보가 없는데도 자정 UTC 인스턴트("2026-07-27T00:00:00.000Z")로 직렬화된다. 이걸
    // parseISODate + 로컬 타임존 포맷(string(from:))으로 되돌리면, UTC보다 시간대가 뒤인
    // 지역에서는 그 인스턴트가 전날 저녁으로 해석돼 하루 밀린 날짜로 그룹핑된다 — 실제 시각이
    // 아니라 "그날"이라는 의미만 담긴 값이므로, 인스턴트로 변환하지 않고 문자열 앞 10자(yyyy-MM-dd)를
    // 그대로 날짜 키로 쓴다. 실제 시각이 의미 있는 필드(커피/운동의 시작·종료 시각 등)에는 쓰면 안
    // 된다 — 그런 필드는 그대로 parseISODate로 파싱해서 로컬 타임존으로 표시하는 게 맞다.
    static func dateOnlyString(fromISO string: String) -> String? {
        guard string.count >= 10 else { return nil }
        return String(string.prefix(10))
    }

    static func combine(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute

        return calendar.date(from: merged) ?? date
    }
}
