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
    let itemSeq: String?
    let entpName: String?
    let itemImage: String?
    let drugShape: String?
    let colorClass: String?
    let chart: String?
    let timings: [String]
}

struct MedicationEntry: Decodable, Identifiable {
    let id: String
    let name: String
    let itemSeq: String?
    let timings: [String]
}

// 공공 약품 DB(식약처 낱알식별정보) 검색 결과 — mind-record 웹 useDrugSearch/DrugItem과 동일한
// 필드만 디코딩한다(약 등록에 그대로 쓰는 것들 + 목록에 보여줄 것들).
struct DrugSearchResponse: Decodable {
    let items: [DrugItem]
}

struct DrugItem: Decodable, Identifiable {
    let itemSeq: String
    let itemName: String
    let entpName: String
    let itemImage: String?
    let drugShape: String?
    let colorClass: String?
    let chart: String?
    var id: String { itemSeq }
}

struct MedicationQuickLogRequest: Encodable {
    let timing: String
    let date: String
}

struct MedicationLogEntry: Decodable, Identifiable {
    let id: String
    let medicationId: String
    let date: String
    let timing: String?
    let taken: Bool
    // 실제로 복용 버튼을 누른 시각 — 캘린더 날짜 요약 시트에서 몇 시에 체크했는지 보여주는 데 쓴다.
    let takenAt: String?
    // 백엔드가 findLogs에서 medication을 include해서 항상 같이 온다 — "이 날의 기록" 목록에 약
    // 이름을 보여주는 데만 쓴다.
    let medication: MedicationSummary?
}

// 캘린더 날짜 요약 시트의 수정 아이콘 — 잘못 고른 시간대를 바로잡는 용도라 timing 하나만 보낸다.
struct MedicationLogUpdateRequest: Encodable {
    let timing: String
}

struct MedicationSummary: Decodable {
    let name: String
}
