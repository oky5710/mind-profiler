import Foundation

// mind-record 웹 EventForm.tsx/useEvents.ts의 EventType과 동일 — 기기의 EventKit 캘린더 일정
// (CalendarEventService/CalendarEventRange)과는 무관한, 사용자가 직접 기록하는 생활 이벤트다.
enum LifeEventType: String, CaseIterable, Identifiable {
    case medicationChange = "MEDICATION_CHANGE"
    case relationshipIssue = "RELATIONSHIP_ISSUE"
    case workStress = "WORK_STRESS"
    case hospitalVisit = "HOSPITAL_VISIT"
    case other = "OTHER"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .medicationChange: "약 변경"
        case .relationshipIssue: "대인관계 문제"
        case .workStress: "업무 스트레스"
        case .hospitalVisit: "병원 진료"
        case .other: "기타"
        }
    }
}

struct LifeEventRequest: Encodable {
    let date: String
    let type: String
    let title: String
    let description: String?
}

struct LifeEventEntry: Decodable, Identifiable {
    let id: String
    let date: String
    let type: String
    let title: String
    let description: String?
}
