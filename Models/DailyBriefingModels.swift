import Foundation

struct DailyBriefingInput {
    let sleepDurationChangeMinutes: Double
    let awakeRatioChangePercent: Double
    let longestContinuousSleepChangeMinutes: Double
    let rmssdChangePercent: Double
}

enum BriefingCaseType {
    case fragmentedSleep
    case shortSleep
    case strongRecovery
    case lowRMSSD
    case ordinaryNight

    var title: String {
        switch self {
        case .fragmentedSleep: "수면이 끊긴 밤"
        case .shortSleep: "짧은 수면 사건"
        case .strongRecovery: "회복의 흔적"
        case .lowRMSSD: "낮아진 회복 신호"
        case .ordinaryNight: "평범한 밤의 기록"
        }
    }
}

enum BriefingCaseDetector {
    static func detect(from input: DailyBriefingInput) -> BriefingCaseType {
        if input.awakeRatioChangePercent >= 30,
           input.longestContinuousSleepChangeMinutes <= -30 {
            return .fragmentedSleep
        }

        if input.sleepDurationChangeMinutes <= -60 {
            return .shortSleep
        }

        if input.awakeRatioChangePercent <= -20,
           input.longestContinuousSleepChangeMinutes >= 30,
           input.rmssdChangePercent >= 10 {
            return .strongRecovery
        }

        if input.rmssdChangePercent <= -20 {
            return .lowRMSSD
        }

        return .ordinaryNight
    }
}
