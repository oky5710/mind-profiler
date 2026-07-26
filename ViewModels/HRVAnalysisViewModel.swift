import Foundation
import HealthKit

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

    struct WorkoutRange: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let displayName: String
        let energyBurnedKcal: Double?
        let distanceMeters: Double?
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
    private(set) var exerciseRanges: [WorkoutRange] = []
    private(set) var sleepRanges: [SleepRange] = []
    private(set) var isHealthKitAuthorized = false
    private(set) var isLoadingHealthKit = false
    private(set) var healthKitErrorMessage: String?
    private(set) var calendarEventRanges: [CalendarEventRange] = []
    private(set) var isCalendarAuthorized = false
    private(set) var isLoadingCalendar = false
    private(set) var calendarErrorMessage: String?

    // HealthKit(rMSSD 등)을 "전체 이력"이 아니라 화면에 보이는 구간의 loadWindowMultiplier배만
    // 불러온다 — rMSSD 계산이 원시 박동 시리즈를 전부 순회하는 무거운 연산이라, 데이터가 몇 년치
    // 쌓여도 매번 전부 다시 계산하지 않기 위함. 스크롤/핀치로 보이는 구간이 이 범위의 안전 여백
    // (prefetchMarginMultiplier배) 밖으로 나가려고 하면 새 위치를 중심으로 다시 불러온다.
    static let loadWindowMultiplier: Double = 5
    // 로드된 구간의 양쪽 여유(각각 (loadWindowMultiplier-1)/2배)를 이만큼 다 쓰면 미리 다음 구간을
    // 불러온다 — 사용자가 실제 가장자리에 닿기 전에 백그라운드 로딩이 끝나 있도록 여유를 준다.
    static let prefetchMarginMultiplier: Double = 1
    // 지금까지 불러온 HealthKit 데이터가 커버하는 실제 기간.
    private var loadedHealthKitRange: ClosedRange<Date>?
    private var isLoadingHealthKitWindow = false

    private var hasLoaded = false
    private var hasCheckedRecentMedian = false
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

    // 최근 30일 중앙값은 스크롤 위치와 무관하게 항상 "오늘 기준"이어야 해서, 아래 windowed 로딩과
    // 별도로 그 30일 구간만 따로 가볍게 조회한다 — 사용자가 몇 달/몇 년 전으로 스크롤해도 이 값은
    // 계속 최신을 유지한다.
    func loadRecentThirtyDayMedianIfNeeded() async {
        guard !hasCheckedRecentMedian else { return }
        hasCheckedRecentMedian = true

        do {
            try await HealthKitService.requestAuthorization()
            recentThirtyDayRMSSDMedian = try await RMSSDThreshold.fetchRecentThirtyDayMedian()
        } catch {
            healthKitErrorMessage = error.localizedDescription
            hasCheckedRecentMedian = false
        }
    }

    // 지금 로딩 중일 때 새로 들어온 요청 — 버리지 않고 여기 남겨서, 지금 도는 로딩이 끝나면
    // 그 사이에 스크롤이 더 진행됐는지 확인해 최신 위치로 이어서 불러오게 한다(가장 최신 요청만
    // 의미가 있으므로 매번 덮어쓴다 — 중간 요청들을 다 큐잉할 필요는 없다).
    private var pendingWindowRequest: (start: Date, end: Date, force: Bool)?

    private func isWithinLoadedRange(start: Date, end: Date) -> Bool {
        guard let loadedHealthKitRange else { return false }
        let margin = end.timeIntervalSince(start) * Self.prefetchMarginMultiplier
        let safeStart = loadedHealthKitRange.lowerBound.addingTimeInterval(margin)
        let safeEnd = loadedHealthKitRange.upperBound.addingTimeInterval(-margin)
        return start >= safeStart && end <= safeEnd
    }

    // 화면에 보이는 구간(visibleStart~visibleEnd)의 loadWindowMultiplier배를 불러온다. 이미 그 구간이
    // prefetchMarginMultiplier배만큼 여유 있게 로드되어 있으면 아무 것도 하지 않는다 — 스크롤/핀치
    // 때마다 호출해도 실제 HealthKit 조회는 가장자리에 가까워질 때만 드물게 일어난다.
    // force가 true면(pull-to-refresh) 이미 로드된 범위와 무관하게 현재 위치 기준으로 무조건 다시 불러온다.
    // 새로 데이터를 불러왔으면 true, 이미 로드되어 있어 아무 것도 안 했으면 false를 반환한다 —
    // 호출부가 그 값을 보고 recomputeRange() 같은 비싼 후처리를 실제로 갱신됐을 때만 하게 한다.
    @discardableResult
    func ensureHealthKitDataLoaded(visibleStart: Date, visibleEnd: Date, force: Bool = false) async -> Bool {
        guard visibleEnd.timeIntervalSince(visibleStart) > 0 else { return false }
        if !force, isWithinLoadedRange(start: visibleStart, end: visibleEnd) { return false }

        guard !isLoadingHealthKitWindow else {
            pendingWindowRequest = (visibleStart, visibleEnd, force)
            return false
        }
        isLoadingHealthKitWindow = true
        defer { isLoadingHealthKitWindow = false }

        var requestStart = visibleStart
        var requestEnd = visibleEnd
        var didReload = false

        // 로딩하는 동안 더 최신 요청(pendingWindowRequest)이 들어왔으면, 이번 결과를 반영한 뒤
        // 그 최신 위치를 이어서 불러온다 — 그렇게 안 하면 로딩 도중 스크롤된 요청이 통째로
        // 사라지고, 그 뒤로 스크롤이 멈추면 다시 시도할 기회 자체가 없다.
        while true {
            if await fetchAndApplyHealthKitWindow(visibleStart: requestStart, visibleEnd: requestEnd) {
                didReload = true
            }
            guard let pending = pendingWindowRequest else { break }
            pendingWindowRequest = nil
            // force로 큐잉된 요청은 이미 그 범위가 로드돼 있어도(예: 방금 끝난 로딩이 우연히
            // 겹쳐서) 건너뛰지 않는다 — pull-to-refresh의 "무조건 새로 받아온다"는 의도를
            // 큐잉 과정에서 잃어버리면 안 된다.
            if !pending.force, isWithinLoadedRange(start: pending.start, end: pending.end) { break }
            requestStart = pending.start
            requestEnd = pending.end
        }
        return didReload
    }

    // 실제 HealthKit 조회 + 배열 갱신 한 번. visibleStart/visibleEnd(1배 폭) 기준으로 그
    // loadWindowMultiplier배 구간을 불러온다.
    private func fetchAndApplyHealthKitWindow(visibleStart: Date, visibleEnd: Date) async -> Bool {
        // 최초 로딩(아직 데이터가 하나도 없음)일 때만 전체 화면 스피너를 보여준다 — 스크롤 중
        // 미리 불러오는 건 눈에 안 띄어야 하므로, 기존 데이터를 그대로 보여준 채 조용히 교체한다.
        let isInitialLoad = loadedHealthKitRange == nil
        if isInitialLoad { isLoadingHealthKit = true }
        defer { if isInitialLoad { isLoadingHealthKit = false } }

        let visibleDomain = visibleEnd.timeIntervalSince(visibleStart)
        let center = visibleStart.addingTimeInterval(visibleDomain / 2)
        let windowDomain = visibleDomain * Self.loadWindowMultiplier
        let windowStart = center.addingTimeInterval(-windowDomain / 2)
        let windowEnd = center.addingTimeInterval(windowDomain / 2)

        do {
            try await HealthKitService.requestAuthorization()

            async let workouts = HealthKitService.fetchWorkoutRanges(start: windowStart, end: windowEnd)
            async let sleep = HealthKitService.fetchSleepStageSamples(start: windowStart, end: windowEnd)
            async let rmssd = HealthKitService.fetchRMSSDSamples(start: windowStart, end: windowEnd)
            async let sdnn = HealthKitService.fetchSDNNSamples(start: windowStart, end: windowEnd)
            let (workoutRanges, sleepSamples, rmssdSamples, sdnnSamples) = try await (workouts, sleep, rmssd, sdnn)

            // 수동으로 입력한 운동 기록(백엔드)도 같은 레인에 합친다 — 실패해도 HealthKit 데이터
            // 표시는 막지 않도록 별도로 무시 가능한 에러 처리.
            let manualRanges = (try? await ExerciseService.allExercises()) ?? []

            let rawRMSSDSamples = rmssdSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableRMSSDPointsHourly = Self.segmentByGap(rawRMSSDSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDPointsDaily = Self.segmentByGap(
                Self.dailyMedian(rawRMSSDSamples),
                gapThreshold: Self.hrvGapThresholdDaily
            )
            let rawSDNNSamples = sdnnSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableSDNNPointsHourly = Self.segmentByGap(rawSDNNSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDMonthlyStats = Self.monthlyStats(rawRMSSDSamples)
            let healthKitWorkouts = workoutRanges.map {
                WorkoutRange(
                    start: $0.start,
                    end: $0.end,
                    displayName: HealthKitService.workoutActivityTypeDisplayName($0.activityType),
                    energyBurnedKcal: $0.energyBurnedKcal,
                    distanceMeters: $0.distanceMeters
                )
            }
            let manualWorkouts = manualRanges.compactMap { entry -> WorkoutRange? in
                guard
                    let start = DateKey.parseISODate(entry.startedAt),
                    let end = DateKey.parseISODate(entry.endedAt),
                    start >= windowStart, start <= windowEnd
                else { return nil }
                return WorkoutRange(start: start, end: end, displayName: entry.type, energyBurnedKcal: nil, distanceMeters: nil)
            }
            exerciseRanges = (healthKitWorkouts + manualWorkouts).sorted { $0.start < $1.start }
            sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)
            isHealthKitAuthorized = true
            loadedHealthKitRange = windowStart...windowEnd
            return true
        } catch {
            healthKitErrorMessage = error.localizedDescription
            // loadedHealthKitRange는 건드리지 않는다 — 다음 스크롤/새로고침 때 "아직 로드 안 됨"
            // 취급으로 자연히 다시 시도된다(별도 재시도 플래그가 필요 없다).
            return false
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
            hasCheckedCalendar = false
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
        HRVStatistics.dailyMedian(samples.map { (date: $0.0, value: $0.1) })
            .map { ($0.date, $0.value) }
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
