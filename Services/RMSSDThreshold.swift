import Foundation

// "오늘의 패턴" 차트의 급격한 rMSSD 저하 강조와 백그라운드 급격한 변화 알림이 정확히 같은 기준을
// 쓰도록 공유한다 — 따로 구현하면 화면에는 안 뜨는데 알림은 오는(혹은 그 반대) 식으로 어긋난다.
enum RMSSDThresholdDirection: String, Codable {
    case low = "LOW"
    case high = "HIGH"
}

struct RMSSDPeriodMedians {
    let morning: Double?
    let afternoon: Double?
    let sleep: Double?

    var values: [Double] { [morning, afternoon, sleep].compactMap { $0 } }
}

struct RMSSDRecentBaseline {
    let overallMedian: Double?
    let periodMedians: RMSSDPeriodMedians
    let sleepRanges: [SleepRange]
}

enum RMSSDThreshold {
    // 기존 "오늘의 패턴" 차트에서 쓰던 급격한 저하 기준(최근 30일 중앙값의 50% 미만)을 그대로 쓴다.
    static let lowMultiplier = 0.5
    // 낮음 기준과 대칭되는 새 기준 — 중앙값의 150% 이상이면 급격히 높아진 것으로 본다.
    static let highMultiplier = 1.5

    static func direction(value: Double, median: Double) -> RMSSDThresholdDirection? {
        if value < median * lowMultiplier { return .low }
        if value >= median * highMultiplier { return .high }
        return nil
    }

    static func fetchRecentThirtyDayBaseline(asOf now: Date = Date()) async throws -> RMSSDRecentBaseline {
        let start = now.addingTimeInterval(-30 * 24 * 60 * 60)
        async let rmssdRequest = HealthKitService.fetchRMSSDSamples(start: start, end: now)
        async let sleepRequest = HealthKitService.fetchSleepStageSamples(start: start, end: now)
        let (samples, sleepSamples) = try await (rmssdRequest, sleepRequest)
        return makeRecentBaseline(samples: samples, sleepRanges: SleepAnalysisService.buildSleepRanges(sleepSamples))
    }

    static func makeRecentBaseline(
        samples: [(date: Date, value: Double)],
        sleepRanges: [SleepRange]
    ) -> RMSSDRecentBaseline {
        var morning: [Double] = []
        var afternoon: [Double] = []
        var sleeping: [Double] = []
        let calendar = Calendar.current

        for sample in samples {
            if sleepRanges.contains(where: { sample.date >= $0.start && sample.date <= $0.end }) {
                sleeping.append(sample.value)
            } else if calendar.component(.hour, from: sample.date) < 12 {
                morning.append(sample.value)
            } else {
                afternoon.append(sample.value)
            }
        }

        return RMSSDRecentBaseline(
            overallMedian: samples.isEmpty ? nil : HRVStatistics.median(samples.map(\.value)),
            periodMedians: RMSSDPeriodMedians(
                morning: morning.isEmpty ? nil : HRVStatistics.median(morning),
                afternoon: afternoon.isEmpty ? nil : HRVStatistics.median(afternoon),
                sleep: sleeping.isEmpty ? nil : HRVStatistics.median(sleeping)
            ),
            sleepRanges: sleepRanges
        )
    }

    static func periodMedian(
        at date: Date,
        baseline: RMSSDRecentBaseline
    ) -> Double? {
        if baseline.sleepRanges.contains(where: { date >= $0.start && date <= $0.end }) {
            return baseline.periodMedians.sleep
        }
        return Calendar.current.component(.hour, from: date) < 12
            ? baseline.periodMedians.morning
            : baseline.periodMedians.afternoon
    }
}
