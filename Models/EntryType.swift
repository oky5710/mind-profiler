import Foundation

enum EntryType: String, CaseIterable, Identifiable {
    case exam, exercise, coffee, mood, medication, symptom, event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exam: "검사"
        case .exercise: "운동"
        case .coffee: "커피"
        case .mood: "기분"
        case .medication: "약복용"
        case .symptom: "증상"
        case .event: "이벤트"
        }
    }

}
