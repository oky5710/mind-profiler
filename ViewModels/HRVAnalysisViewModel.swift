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

    private(set) var examPoints: [ExamPoint] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var wearableHRVPointsHourly: [HRVPoint] = []
    private(set) var wearableHRVPointsDaily: [HRVPoint] = []
    private(set) var wearableHRVMonthlyStats: [MonthlyHRVStat] = []
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
            let (hrvSamples, workoutRanges, sleepSamples) = try await (hrv, workouts, sleep)

            let rawSamples = hrvSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableHRVPointsHourly = Self.segmentByGap(rawSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableHRVPointsDaily = Self.segmentByGap(
                Self.dailyMedian(rawSamples),
                gapThreshold: Self.hrvGapThresholdDaily
            )
            wearableHRVMonthlyStats = Self.monthlyStats(rawSamples)
            exerciseRanges = workoutRanges.map { RangeInterval(start: $0.start, end: $0.end) }
            sleepRanges = sleepSamples.map { RangeInterval(start: $0.start, end: $0.end) }
            isHealthKitAuthorized = true
        } catch {
            healthKitErrorMessage = error.localizedDescription
        }
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
