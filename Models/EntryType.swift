import Foundation

enum EntryType: String, CaseIterable, Identifiable {
    case exam, exercise, coffee, mood, medication, event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exam: "검사"
        case .exercise: "운동"
        case .coffee: "커피"
        case .mood: "기분"
        case .medication: "약복용"
        case .event: "이벤트"
        }
    }

    var subtitle: String {
        switch self {
        case .exam: "정신과 HRV 검사 결과"
        case .exercise: "종류/시간/강도"
        case .coffee: "종류/시간/메모"
        case .mood: "1~5점 이모지"
        case .medication: "복용 시간대 처리"
        case .event: "약 변경/스트레스/병원 진료 등"
        }
    }

    var isImplemented: Bool {
        switch self {
        case .mood, .coffee, .exam, .exercise, .medication: true
        case .event: false
        }
    }
}
