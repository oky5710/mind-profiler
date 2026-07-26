import Foundation

enum ReminderRepeatType: String, CaseIterable, Identifiable, Codable {
    case daily = "DAILY"
    case weekly = "WEEKLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "매일"
        case .weekly: "매주"
        }
    }
}

enum ReminderWeekday {
    // Foundation의 Calendar.Component.weekday(1=일요일...7=토요일)와 그대로 맞춘다 — 변환 없이
    // DateComponents.weekday에 넣어 로컬 알림 트리거를 만들 수 있게.
    static let all = 1...7
    static let shortLabels = ["일", "월", "화", "수", "목", "금", "토"]

    static func shortLabel(for weekday: Int) -> String {
        guard shortLabels.indices.contains(weekday - 1) else { return "" }
        return shortLabels[weekday - 1]
    }
}

struct MedicationReminderRequest: Encodable {
    let timing: String
    let repeatType: String
    let weekdays: [Int]
    let time: String
    let startDate: String
    let endDate: String?
}

struct MedicationReminderEntry: Decodable, Identifiable {
    let id: String
    let timing: String
    let repeatType: String
    let weekdays: [Int]
    let time: String
    let startDate: String
    let endDate: String?
}
