import Foundation

// 긍정/부정 각 8개, 4x4 그리드로 보여준다(RMSSDEventEntryForm) — allCases 순서가 그리드 순서(긍정
// 두 줄 다음 부정 두 줄)와 그대로 같아야 하므로 선언 순서를 바꾸지 않는다.
enum RMSSDEmotionCategory {
    case positive
    case negative
}

// rMSSD가 최근 30일 중앙값 대비 급격히 낮아지거나(RMSSDThresholdDirection.low) 높아졌을 때
// (.high) 기기가 감지해 알림을 보내면, 사용자가 그때 고르는 감정 — 1~5점 기분 점수(MoodService)와는
// 다른, 이 알림 전용의 별도 카테고리다.
enum RMSSDEmotion: String, CaseIterable, Identifiable, Codable {
    // 긍정
    case joy = "JOY"
    case calm = "CALM"
    case confidence = "CONFIDENCE"
    case excitement = "EXCITEMENT"
    case love = "LOVE"
    case gratitude = "GRATITUDE"
    case satisfaction = "SATISFACTION"
    case thrill = "THRILL"
    // 부정
    case anxiety = "ANXIETY"
    case depression = "DEPRESSION"
    case anger = "ANGER"
    case stress = "STRESS"
    case frustration = "FRUSTRATION"
    case sadness = "SADNESS"
    case fatigue = "FATIGUE"
    case fear = "FEAR"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .joy: "기쁨"
        case .calm: "평온"
        case .confidence: "자신감"
        case .excitement: "설렘"
        case .love: "사랑"
        case .gratitude: "감사"
        case .satisfaction: "만족"
        case .thrill: "신남"
        case .anxiety: "불안"
        case .depression: "우울"
        case .anger: "분노"
        case .stress: "스트레스"
        case .frustration: "답답함"
        case .sadness: "슬픔"
        case .fatigue: "피곤"
        case .fear: "두려움"
        }
    }

    var category: RMSSDEmotionCategory {
        switch self {
        case .joy, .calm, .confidence, .excitement, .love, .gratitude, .satisfaction, .thrill:
            .positive
        case .anxiety, .depression, .anger, .stress, .frustration, .sadness, .fatigue, .fear:
            .negative
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
