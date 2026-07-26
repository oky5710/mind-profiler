import Foundation

// 탭했을 때 보여줄 수면 단계 구성과 추정 수면 점수. "오늘의 패턴"과 "보고서" 화면이 공유해서 쓴다.
struct SleepRange: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let stageDurations: [HealthKitService.SleepStage: TimeInterval]
    // 애플 Health 앱의 수면 점수는 HealthKit 공개 API로 노출되지 않아, 애플이 공개한 것과 같은
    // 가중치 구성(수면시간 50 + 취침시간 일관성 30 + 각성 20)으로 흉내 낸 추정치일 뿐이다 —
    // 애플의 정확한 채점 곡선은 비공개라 실제 Health 앱 점수와는 다를 수 있다.
    let estimatedScore: Int
}

enum SleepAnalysisService {
    // 자다가 잠깐 깨는 것까지 별도 수면으로 쪼개지 않도록, 1시간 이내로 떨어진 수면 구간은 하나로 합친다.
    static let mergeGapThreshold: TimeInterval = 60 * 60

    // 단계별로 보여줄 순서 — 중요도가 높은 깊은 수면/렘을 앞에 둔다.
    static let stageDisplayOrder: [HealthKitService.SleepStage] = [.deep, .rem, .core, .unspecified]

    static func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...: "좋음"
        case 60..<80: "보통"
        default: "나쁨"
        }
    }

    static func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        return "\(totalMinutes / 60)시간 \(totalMinutes % 60)분"
    }

    // 오후 9시(21시) 이후에 시작해서 다음날 오전 10시 이전에 끝나는 수면을 그날 밤으로 본다 —
    // 세션이 속하는 "밤 날짜"는 시작 시각의 시(hour)가 10시 이전이면 전날로 당기고, 그 외엔 시작한
    // 날짜 그대로 쓴다. 보고서의 수면 차트(x축 날짜 배정)와 전날 수면시간 상관계수(날짜별 키)가
    // 같은 기준을 써야, 자정 넘어 시작한 세션이 차트에서는 전날 것으로 보이는데 상관계수 계산에서는
    // 그날 것으로 잡히는 식으로 서로 어긋나지 않는다.
    static func nightLabel(for date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour < 10 ? (calendar.date(byAdding: .day, value: -1, to: day) ?? day) : day
    }

    // 자다가 잠깐 깨는 간격(maxGap 이내)은 별도 수면으로 쪼개지 않고 하나로 합치되, 합쳐진 구간 안에서
    // 단계별로 실제 잔 시간이 얼마인지는 그대로 유지해서 탭했을 때 보여준다.
    static func buildSleepRanges(
        _ samples: [(start: Date, end: Date, stage: HealthKitService.SleepStage)],
        maxGap: TimeInterval = mergeGapThreshold
    ) -> [SleepRange] {
        let sorted = samples.sorted { $0.start < $1.start }
        var ranges: [SleepRange] = []
        var currentGroup: [(start: Date, end: Date, stage: HealthKitService.SleepStage)] = []
        var currentGroupEnd: Date?

        func flushGroup() {
            guard let start = currentGroup.map(\.start).min(), let end = currentGroupEnd else { return }
            var durations: [HealthKitService.SleepStage: TimeInterval] = [:]
            for sample in currentGroup {
                durations[sample.stage, default: 0] += sample.end.timeIntervalSince(sample.start)
            }
            // 취침시간 일관성 점수는 이 밤 이전의 밤들과 비교해야 해서, 지금까지 쌓인 ranges(과거 밤들)를
            // 그대로 넘긴다 — samples가 시간순 정렬이라 ranges는 항상 currentGroup보다 앞선 밤들이다.
            let score = estimatedSleepScore(start: start, end: end, stageDurations: durations, previousNights: ranges)
            ranges.append(SleepRange(start: start, end: end, stageDurations: durations, estimatedScore: score))
            currentGroup = []
            currentGroupEnd = nil
        }

        for sample in sorted {
            if let groupEnd = currentGroupEnd, sample.start.timeIntervalSince(groupEnd) > maxGap {
                flushGroup()
            }
            currentGroup.append(sample)
            currentGroupEnd = max(currentGroupEnd ?? sample.end, sample.end)
        }
        flushGroup()

        return ranges
    }

    // 애플이 공개한 수면 점수 구성: 수면시간 50점(8시간 기준) + 취침시간 일관성 30점 + 각성 20점.
    private static let sleepScoreTargetDuration: TimeInterval = 8 * 60 * 60
    // 일관성 비교 기준 — 최근 일주일치 취침 시각과 비교한다. ReportViewModel이 수면 데이터를
    // 가져올 때 이 값만큼의 이전 밤도 같이 가져와야 기간 첫날들의 점수가 "비교할 밤이 부족해서
    // 만점" 처리되지 않으므로 private이 아니다.
    static let bedtimeConsistencyWindow = 6
    private static let bedtimeConsistencyToleranceMinutes: Double = 90
    private static let interruptionTolerance: TimeInterval = 60 * 60

    private static func estimatedSleepScore(
        start: Date,
        end: Date,
        stageDurations: [HealthKitService.SleepStage: TimeInterval],
        previousNights: [SleepRange]
    ) -> Int {
        let trackedDuration = stageDurations.values.reduce(0, +)
        let durationScore = min(50.0, (trackedDuration / sleepScoreTargetDuration) * 50)

        // 비교할 과거 밤이 부족하면(초기 사용) 불리하지 않도록 만점을 준다.
        let recentBedtimes = previousNights.suffix(bedtimeConsistencyWindow).map(\.start)
        let consistencyScore: Double
        if recentBedtimes.count >= 2 {
            let currentMinutes = bedtimeMinutesSinceNoon(start)
            let averageMinutes = recentBedtimes.map(bedtimeMinutesSinceNoon).reduce(0, +) / Double(recentBedtimes.count)
            let deviation = abs(currentMinutes - averageMinutes)
            consistencyScore = max(0, 30 * (1 - deviation / bedtimeConsistencyToleranceMinutes))
        } else {
            consistencyScore = 30
        }

        let awakeDuration = max(0, end.timeIntervalSince(start) - trackedDuration)
        let interruptionScore = max(0, 20 * (1 - awakeDuration / interruptionTolerance))

        let total = Int((durationScore + consistencyScore + interruptionScore).rounded())
        return min(100, max(0, total))
    }

    // 취침 시각은 자정을 넘나들어서(23:30 vs 00:15) 단순 시:분 비교로는 안 되고, 정오를 기준으로
    // 밀어서(자정=720분) 비교해야 자정 전후 취침 시각들이 가깝게 계산된다.
    private static func bedtimeMinutesSinceNoon(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutesSinceMidnight = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        let shifted = minutesSinceMidnight - 12 * 60
        return shifted < 0 ? shifted + 24 * 60 : shifted
    }
}
