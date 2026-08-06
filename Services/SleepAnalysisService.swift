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
    // 자다가 깬 뒤 다시 잠든 경우를 별도 수면으로 쪼개지 않도록, 2시간 이하로 떨어진 수면 구간은
    // 하나의 밤으로 합친다. 사이의 공백은 수면시간에 더하지 않고 각성 구간으로만 취급한다.
    static let mergeGapThreshold: TimeInterval = 2 * 60 * 60

    // 단계별로 보여줄 순서 — 중요도가 높은 깊은 수면/렘을 앞에 둔다.
    static let stageDisplayOrder: [HealthKitService.SleepStage] = [.deep, .rem, .core, .unspecified]

    static func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...: "좋음"
        case 60..<80: "보통"
        default: "나쁨"
        }
    }

    nonisolated static func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        return "\(totalMinutes / 60)시간 \(totalMinutes % 60)분"
    }

    static func mergeIntervals(
        _ intervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        var merged: [(start: Date, end: Date)] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    // 여러 소스(예: 아이폰+워치)가 같은 시간대에 각각 단계 샘플을 남기면 단순 합산은 그 겹치는 시간을
    // 두 번 센다 — 겹치는 구간은 더 구체적인 단계 쪽에만 귀속시켜 실제 경과 시간을 넘지 않게 한다.
    // stageDisplayOrder(표시 순서)와 값은 같지만, 이건 "우선순위" 목적의 별도 정의다 — 표시 순서를
    // 바꿔도 이 겹침 해소 규칙이 조용히 같이 바뀌면 안 된다.
    private static let stageOverlapPriority: [HealthKitService.SleepStage] = [.deep, .rem, .core, .unspecified]

    private static func nonOverlappingStageDurations(
        _ samples: [(start: Date, end: Date, stage: HealthKitService.SleepStage)]
    ) -> [HealthKitService.SleepStage: TimeInterval] {
        var durations: [HealthKitService.SleepStage: TimeInterval] = [:]
        var claimed: [(start: Date, end: Date)] = []

        for stage in stageOverlapPriority {
            let ownIntervals = samples
                .filter { $0.stage == stage }
                .map { (start: $0.start, end: $0.end) }
            guard !ownIntervals.isEmpty else { continue }

            let merged = mergeIntervals(ownIntervals)
            let uncovered = subtractIntervals(merged, removing: claimed)
            let duration = uncovered.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            if duration > 0 {
                durations[stage] = duration
            }
            claimed = mergeIntervals(claimed + merged)
        }

        return durations
    }

    // `intervals`에서 `removal`과 겹치는 부분을 잘라내고 남은 조각들을 돌려준다. `removal`은 이미
    // mergeIntervals를 거쳐 겹치지 않는 상태라고 가정한다.
    private static func subtractIntervals(
        _ intervals: [(start: Date, end: Date)],
        removing removal: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        guard !removal.isEmpty else { return intervals }

        var result: [(start: Date, end: Date)] = []
        for interval in intervals {
            var pieces: [(start: Date, end: Date)] = [interval]
            for cut in removal {
                pieces = pieces.flatMap { piece -> [(start: Date, end: Date)] in
                    guard cut.end > piece.start, cut.start < piece.end else { return [piece] }
                    var remaining: [(start: Date, end: Date)] = []
                    if cut.start > piece.start {
                        remaining.append((start: piece.start, end: cut.start))
                    }
                    if cut.end < piece.end {
                        remaining.append((start: cut.end, end: piece.end))
                    }
                    return remaining
                }
            }
            result.append(contentsOf: pieces)
        }
        return result
    }

    // range 안에서 "각성"으로 볼 구간 = 명시적 .awake 타임라인 샘플 + 샘플이 전혀 없는 빈 구간(공백).
    // buildSleepRanges가 두 수면 구간을 최대 2시간까지 하나로 합치는데, 그 사이(예: 워치를 벗어둔 시간)
    // 어떤 카테고리 샘플도 없다면 그 공백은 실제로 잠들어 있었는지 알 수 없다 — 그런 미확인 시간을
    // 수면으로 잡아 총 수면시간을 부풀리는 대신 각성으로 본다(문서(features.md)에 쓴 그대로).
    static func awakeIntervals(
        within range: SleepRange,
        timeline: [(start: Date, end: Date, stage: HealthKitService.SleepTimelineStage)]
    ) -> [(start: Date, end: Date)] {
        guard range.end > range.start else { return [] }

        let explicitAwake = timeline
            .filter { $0.stage == .awake && $0.end > range.start && $0.start < range.end }
            .map { (start: max($0.start, range.start), end: min($0.end, range.end)) }

        let covered = timeline
            .filter { $0.end > range.start && $0.start < range.end }
            .map { (start: max($0.start, range.start), end: min($0.end, range.end)) }
        let uncoveredGaps = subtractIntervals(
            [(start: range.start, end: range.end)],
            removing: mergeIntervals(covered)
        )

        return mergeIntervals(explicitAwake + uncoveredGaps)
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
            let durations = nonOverlappingStageDurations(currentGroup)
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
    nonisolated static func bedtimeMinutesSinceNoon(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutesSinceMidnight = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        let shifted = minutesSinceMidnight - 12 * 60
        return shifted < 0 ? shifted + 24 * 60 : shifted
    }
}
