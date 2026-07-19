import Foundation

// mind-record 웹 useMedications.ts의 DoseTiming/DOSE_TIMING_LABELS와 동일.
enum MedicationTiming: String, CaseIterable, Identifiable {
    case morning = "MORNING"
    case lunch = "LUNCH"
    case dinner = "DINNER"
    case bedtime = "BEDTIME"
    case asNeeded = "AS_NEEDED"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "아침"
        case .lunch: "점심"
        case .dinner: "저녁"
        case .bedtime: "취침전"
        case .asNeeded: "필요시"
        }
    }
}

struct MedicationRequest: Encodable {
    let name: String
    let timings: [String]
}

struct MedicationEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let timings: [String]
}

struct MedicationQuickLogRequest: Encodable {
    let timing: String
    let date: String
}

struct MedicationLogEntry: Decodable {
    let id: String
    let medicationId: String
    let date: String
    let timing: String?
    let taken: Bool
}
