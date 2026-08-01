import Foundation

struct SleepContinuityMetrics {
    let totalAwakeDuration: TimeInterval
    let awakeningCount: Int
    let longestAwakening: TimeInterval
    let longestContinuousSleep: TimeInterval
    let sleepWindowDuration: TimeInterval

    var awakeRatio: Double {
        guard sleepWindowDuration > 0 else { return 0 }
        return totalAwakeDuration / sleepWindowDuration
    }

    var continuousSleepRatio: Double {
        guard sleepWindowDuration > 0 else { return 0 }
        return longestContinuousSleep / sleepWindowDuration
    }
}

struct SleepContinuityBaseline {
    let awakeRatioMedian: Double
    let longestAwakeningMedian: TimeInterval
    let continuousSleepRatioMedian: Double
}

enum RelativeLevel {
    case lower
    case typical
    case higher
}

struct SleepContinuitySummary {
    let title: String
    let detail: String
}

extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

func makeSleepContinuityBaseline(
    from nights: [SleepContinuityMetrics]
) -> SleepContinuityBaseline? {
    guard
        let awakeRatioMedian = nights.map(\.awakeRatio).median,
        let longestAwakeningMedian = nights.map(\.longestAwakening).median,
        let continuousSleepRatioMedian = nights.map(\.continuousSleepRatio).median
    else {
        return nil
    }

    return SleepContinuityBaseline(
        awakeRatioMedian: awakeRatioMedian,
        longestAwakeningMedian: longestAwakeningMedian,
        continuousSleepRatioMedian: continuousSleepRatioMedian
    )
}

func relativeLevel(
    current: Double,
    baseline: Double,
    tolerance: Double = 0.2
) -> RelativeLevel {
    guard baseline > 0 else { return .typical }
    let ratio = current / baseline
    if ratio < 1 - tolerance { return .lower }
    if ratio > 1 + tolerance { return .higher }
    return .typical
}

enum SleepContinuitySummaryBuilder {
    static func build(
        current: SleepContinuityMetrics,
        baseline: SleepContinuityBaseline?
    ) -> SleepContinuitySummary {
        guard let baseline else {
            return SleepContinuitySummary(
                title: "수면 연속성 기록을 모으는 중이에요.",
                detail: "평소와 비교할 데이터가 부족해요. 수면 시 애플워치를 착용해주세요."
            )
        }

        let awakeLevel = relativeLevel(
            current: current.awakeRatio,
            baseline: baseline.awakeRatioMedian
        )
        let continuousLevel = relativeLevel(
            current: current.continuousSleepRatio,
            baseline: baseline.continuousSleepRatioMedian
        )

        switch (awakeLevel, continuousLevel) {
        case (.higher, .lower):
            return SleepContinuitySummary(
                title: "평소보다 수면이 자주 끊긴 밤이었어요.",
                detail: "각성 비율이 높았고, 가장 긴 연속 수면도 평소보다 짧았어요. 오늘은 스스로에게 조금 더 여유를 선물해 보세요. 충분한 휴식이 도움이 될 수 있어요."
            )
        case (.higher, .typical), (.higher, .higher):
            return SleepContinuitySummary(
                title: "평소보다 깨어 있던 시간이 길었어요.",
                detail: "다만 가장 긴 연속 수면은 평소 수준을 유지했어요."
            )
        case (.typical, .lower):
            return SleepContinuitySummary(
                title: "전체 각성은 평소 수준이에요.",
                detail: "하지만 한 번에 이어서 잔 시간은 평소보다 짧았어요."
            )
        case (.lower, .higher):
            return SleepContinuitySummary(
                title: "몸이 편안하게 회복된 밤이었어요.",
                detail: "깨어 있던 비율이 낮고, 긴 수면 구간도 평소보다 길었어요. 오늘은 가벼운 마음으로 하루를 시작해 보세요."
            )
        case (.lower, .typical):
            return SleepContinuitySummary(
                title: "평소보다 깨어 있던 시간이 적었어요.",
                detail: "가장 긴 연속 수면은 평소와 비슷했어요."
            )
        case (.typical, .higher):
            return SleepContinuitySummary(
                title: "수면 연속성이 비교적 좋았어요.",
                detail: "각성 비율은 평소 수준이고, 긴 수면 구간은 평소보다 길었어요."
            )
        case (.typical, .typical):
            return SleepContinuitySummary(
                title: "평소와 비슷한 수면 패턴이에요.",
                detail: "각성 비율과 가장 긴 연속 수면 모두 최근 한 달 수준이었어요."
            )
        case (.lower, .lower):
            return SleepContinuitySummary(
                title: "깨어 있던 시간은 적었어요.",
                detail: "다만 수면이 여러 구간으로 나뉘어 가장 긴 연속 수면은 짧았어요."
            )
        }
    }
}
