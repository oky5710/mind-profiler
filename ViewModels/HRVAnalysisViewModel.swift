import Foundation

@MainActor
@Observable
final class HRVAnalysisViewModel {
    struct ExamPoint: Identifiable {
        let date: Date
        let sdnn: Double
        var id: Date { date }
    }

    struct HRVPoint: Identifiable {
        let date: Date
        let value: Double
        let segment: Int
        var id: Date { date }
    }

    struct MonthlyHRVStat: Identifiable {
        let monthStart: Date
        let min: Double
        let max: Double
        let median: Double
        var id: Date { monthStart }
    }

    struct RangeInterval: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    // mind-record 웹의 GAP_THRESHOLD_MS(3시간)와 동일 — 정상 측정 간격(~2시간)보다 조금 더 긴 값.
    private static let hrvGapThresholdHourly: TimeInterval = 3 * 60 * 60
    private static let hrvGapThresholdDaily: TimeInterval = 1.5 * 24 * 60 * 60
    // 자다가 잠깐 깨는 것까지 별도 수면으로 쪼개지 않도록, 1시간 이내로 떨어진 수면 구간은 하나로 합친다.
    private static let sleepMergeGapThreshold: TimeInterval = 60 * 60

    private(set) var examPoints: [ExamPoint] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // 시간별/일별 HRV 라인은 화면에서 뺐고(rMSSD로 대체), 월별 막대 집계에만 원시 HRV 샘플을 계속 쓴다.
    private(set) var wearableHRVMonthlyStats: [MonthlyHRVStat] = []
    // rMSSD는 HealthKit이 직접 주지 않아 원시 박동 시리즈에서 계산함 (HealthKitService.fetchRMSSDSamples 참고).
    private(set) var wearableRMSSDPointsHourly: [HRVPoint] = []
    private(set) var wearableRMSSDPointsDaily: [HRVPoint] = []
    private(set) var exerciseRanges: [RangeInterval] = []
    private(set) var sleepRanges: [RangeInterval] = []
    private(set) var isHealthKitAuthorized = false
    private(set) var isLoadingHealthKit = false
    private(set) var healthKitErrorMessage: String?

    private var hasLoaded = false
    private var hasCheckedHealthKit = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let examList = try await ExamService.allExams()

            examPoints = examList
                .compactMap { entry -> ExamPoint? in
                    guard let date = DateKey.parseISODate(entry.examinedAt) else { return nil }
                    return ExamPoint(date: date, sdnn: entry.sdnn)
                }
                .sorted { $0.date < $1.date }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadWearableHRVIfNeeded() async {
        guard !hasCheckedHealthKit else { return }
        hasCheckedHealthKit = true
        isLoadingHealthKit = true
        defer { isLoadingHealthKit = false }

        do {
            try await HealthKitService.requestAuthorization()

            async let hrv = HealthKitService.fetchHRVSamples()
            async let workouts = HealthKitService.fetchWorkoutRanges()
            async let sleep = HealthKitService.fetchSleepRanges()
            async let rmssd = HealthKitService.fetchRMSSDSamples()
            let (hrvSamples, workoutRanges, sleepSamples, rmssdSamples) = try await (hrv, workouts, sleep, rmssd)

            let rawSamples = hrvSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableHRVMonthlyStats = Self.monthlyStats(rawSamples)

            let rawRMSSDSamples = rmssdSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableRMSSDPointsHourly = Self.segmentByGap(rawRMSSDSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDPointsDaily = Self.segmentByGap(
                Self.dailyMedian(rawRMSSDSamples),
                gapThreshold: Self.hrvGapThresholdDaily
            )
            exerciseRanges = workoutRanges.map { RangeInterval(start: $0.start, end: $0.end) }
            sleepRanges = Self.mergeCloseRanges(sleepSamples, maxGap: Self.sleepMergeGapThreshold)
                .map { RangeInterval(start: $0.start, end: $0.end) }
            isHealthKitAuthorized = true
        } catch {
            healthKitErrorMessage = error.localizedDescription
        }
    }

    private static func mergeCloseRanges(
        _ ranges: [(start: Date, end: Date)],
        maxGap: TimeInterval
    ) -> [(start: Date, end: Date)] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []
        for range in sorted {
            if let last = merged.last, range.start.timeIntervalSince(last.end) <= maxGap {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func segmentByGap(_ samples: [(Date, Double)], gapThreshold: TimeInterval) -> [HRVPoint] {
        var points: [HRVPoint] = []
        var segment = 0
        var previousDate: Date?

        for (date, value) in samples {
            if let previousDate, date.timeIntervalSince(previousDate) > gapThreshold {
                segment += 1
            }
            points.append(HRVPoint(date: date, value: value, segment: segment))
            previousDate = date
        }

        return points
    }

    private static func dailyMedian(_ samples: [(Date, Double)]) -> [(Date, Double)] {
        var groups: [Date: [Double]] = [:]
        for (date, value) in samples {
            groups[Calendar.current.startOfDay(for: date), default: []].append(value)
        }
        return groups
            .map { (day, values) in (day, median(values)) }
            .sorted { $0.0 < $1.0 }
    }

    private static func monthlyStats(_ samples: [(Date, Double)]) -> [MonthlyHRVStat] {
        let calendar = Calendar.current
        var groups: [DateComponents: [Double]] = [:]
        for (date, value) in samples {
            groups[calendar.dateComponents([.year, .month], from: date), default: []].append(value)
        }
        return groups
            .compactMap { components, values -> MonthlyHRVStat? in
                guard let monthStart = calendar.date(from: components) else { return nil }
                let sorted = values.sorted()
                return MonthlyHRVStat(
                    monthStart: monthStart,
                    min: sorted.first ?? 0,
                    max: sorted.last ?? 0,
                    median: median(sorted)
                )
            }
            .sorted { $0.monthStart < $1.monthStart }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

}
