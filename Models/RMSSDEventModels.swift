import Foundation

// rMSSD가 최근 30일 중앙값 대비 급격히 낮아지거나(RMSSDThresholdDirection.low) 높아졌을 때
// (.high) 기기가 감지해 알림을 보내면, 사용자가 그때 고르는 감정 — 1~5점 기분 점수(MoodService)와는
// 다른, 이 알림 전용의 별도 카테고리다.
enum RMSSDEmotion: String, CaseIterable, Identifiable, Codable {
    case anxiety = "ANXIETY"
    case stress = "STRESS"
    case irritation = "IRRITATION"
    case sadness = "SADNESS"
    case fatigue = "FATIGUE"
    case calm = "CALM"
    case joy = "JOY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anxiety: "불안"
        case .stress: "스트레스"
        case .irritation: "짜증"
        case .sadness: "슬픔"
        case .fatigue: "피곤"
        case .calm: "평온"
        case .joy: "기쁨"
        }
    }
}

struct RMSSDEventRequest: Encodable {
    let occurredAt: String
    let rmssdValue: Double
    let direction: String
    let emotion: String
    let note: String?
}

struct RMSSDEventEntry: Decodable, Identifiable {
    let id: String
    let occurredAt: String
    let rmssdValue: Double
    let direction: String
    let emotion: String
    let note: String?
}
