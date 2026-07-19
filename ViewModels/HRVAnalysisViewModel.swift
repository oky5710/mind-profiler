import Foundation

@MainActor
@Observable
final class HRVAnalysisViewModel {
    struct ExamPoint: Identifiable {
        let date: Date
        let rmssd: Double
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
        let q1: Double
        let median: Double
        let q3: Double
        let cv: Double?
        var id: Date { monthStart }
    }

    struct RangeInterval: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    struct CalendarEventRange: Identifiable {
        let id = UUID()
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let category: CalendarEventCategory
    }

    // mind-record 웹의 GAP_THRESHOLD_MS(3시간)와 동일 — 정상 측정 간격(~2시간)보다 조금 더 긴 값.
    private static let hrvGapThresholdHourly: TimeInterval = 3 * 60 * 60
    private static let hrvGapThresholdDaily: TimeInterval = 1.5 * 24 * 60 * 60

    private(set) var examPoints: [ExamPoint] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // rMSSD는 HealthKit이 직접 주지 않아 원시 박동 시리즈에서 계산함 (HealthKitService.fetchRMSSDSamples 참고).
    // 시간별/일별 라인, 월별 막대 집계 모두 이 rMSSD 기준으로 통일한다.
    private(set) var wearableRMSSDMonthlyStats: [MonthlyHRVStat] = []
    private(set) var wearableRMSSDPointsHourly: [HRVPoint] = []
    private(set) var wearableRMSSDPointsDaily: [HRVPoint] = []
    // SDNN은 rMSSD보다 덜 중요한 참고값이라 시간별 모드에서만 옅게 같이 보여준다.
    private(set) var wearableSDNNPointsHourly: [HRVPoint] = []
    // 최근 30일 rMSSD 중앙값 — 라인 차트에 점선으로 표시.
    private(set) var recentThirtyDayRMSSDMedian: Double?
    private(set) var exerciseRanges: [RangeInterval] = []
    private(set) var sleepRanges: [SleepRange] = []
    private(set) var isHealthKitAuthorized = false
    private(set) var isLoadingHealthKit = false
    private(set) var healthKitErrorMessage: String?
    private(set) var calendarEventRanges: [CalendarEventRange] = []
    private(set) var isCalendarAuthorized = false
    private(set) var isLoadingCalendar = false
    private(set) var calendarErrorMessage: String?

    private var hasLoaded = false
    private var hasCheckedHealthKit = false
    private var hasCheckedCalendar = false

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
                    return ExamPoint(date: date, rmssd: entry.rmssd)
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

            async let workouts = HealthKitService.fetchWorkoutRanges()
            async let sleep = HealthKitService.fetchSleepStageSamples()
            async let rmssd = HealthKitService.fetchRMSSDSamples()
            async let sdnn = HealthKitService.fetchSDNNSamples()
            let (workoutRanges, sleepSamples, rmssdSamples, sdnnSamples) = try await (workouts, sleep, rmssd, sdnn)

            let rawRMSSDSamples = rmssdSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableRMSSDPointsHourly = Self.segmentByGap(rawRMSSDSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDPointsDaily = Self.segmentByGap(
                Self.dailyMedian(rawRMSSDSamples),
                gapThreshold: Self.hrvGapThresholdDaily
            )
            let rawSDNNSamples = sdnnSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableSDNNPointsHourly = Self.segmentByGap(rawSDNNSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDMonthlyStats = Self.monthlyStats(rawRMSSDSamples)
            let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            let recentRMSSDValues = rawRMSSDSamples.filter { $0.0 >= thirtyDaysAgo }.map(\.1)
            recentThirtyDayRMSSDMedian = recentRMSSDValues.isEmpty ? nil : HRVStatistics.median(recentRMSSDValues)
            exerciseRanges = workoutRanges.map { RangeInterval(start: $0.start, end: $0.end) }
            sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)
            isHealthKitAuthorized = true
        } catch {
            healthKitErrorMessage = error.localizedDescription
        }
    }

    func loadCalendarEventsIfNeeded() async {
        guard !hasCheckedCalendar else { return }
        hasCheckedCalendar = true
        isLoadingCalendar = true
        defer { isLoadingCalendar = false }

        do {
            try await CalendarEventService.requestAuthorization()
            calendarEventRanges = await CalendarEventService.fetchEvents()
                .map { event in
                    CalendarEventRange(
                        title: event.title,
                        start: event.start,
                        end: event.end,
                        isAllDay: event.isAllDay,
                        location: event.location,
                        category: event.category
                    )
                }
                .sorted { $0.start < $1.start }
            isCalendarAuthorized = true
        } catch {
            calendarErrorMessage = error.localizedDescription
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
            .map { (day, values) in (day, HRVStatistics.median(values)) }
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
                let quartiles = HRVStatistics.quartiles(sorted)
                return MonthlyHRVStat(
                    monthStart: monthStart,
                    min: sorted.first ?? 0,
                    max: sorted.last ?? 0,
                    q1: quartiles.q1,
                    median: quartiles.median,
                    q3: quartiles.q3,
                    cv: HRVStatistics.coefficientOfVariation(sorted)
                )
            }
            .sorted { $0.monthStart < $1.monthStart }
    }
}
