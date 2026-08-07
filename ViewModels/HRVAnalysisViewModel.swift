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

    struct HRVPoint: Identifiable, DatedPoint {
        let date: Date
        let value: Double
        let segment: Int
        var id: Date { date }
    }

    struct DailySleepPoint: Identifiable, DatedPoint {
        // 해당 밤이 시작되는 날짜의 자정. rMSSD/안정시 심박수 일별 포인트와 같은 x 좌표를 쓴다.
        let date: Date
        let hours: Double
        var id: Date { date }
    }

    struct DailyDaylightPoint: Identifiable, DatedPoint {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    struct RMSSDBaselineSegment: Identifiable {
        let start: Date
        let end: Date
        let value: Double
        var id: Date { start }
    }

    struct MonthlyHRVStat: Identifiable {
        let monthStart: Date
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

    // 시간별 모드 간트 차트 아래 아이콘 레인에 찍는 커피/약복용/증상/이벤트 마커. 모두 "그 순간에 일어난
    // 일"이라 구간이 아니라 점 하나로 표현한다.
    enum DailyMarkerKind {
        case coffee, medication, symptom, event
    }

    struct DailyMarker: Identifiable {
        // 매번 새 UUID를 만들면(계산 프로퍼티 dailyMarkers가 접근할 때마다 재평가되므로) 스크롤 같은
        // 평범한 리렌더에도 SwiftUI가 모든 마크를 "지웠다가 새로 추가됨"으로 취급해 차트를 불필요하게
        // 다시 그린다 — 원본 로그의 안정적인 id(약복용은 날짜+시간대 키)로 고정해야 한다.
        let id: String
        let date: Date
        let kind: DailyMarkerKind
        let title: String
        let intensity: Int?
        let description: String?
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
    // 최근 30일 rMSSD를 수면 중/비수면 오전/비수면 오후로 나눈 중앙값.
    private(set) var recentThirtyDayPeriodMedians: RMSSDPeriodMedians?
    private(set) var exerciseRanges: [WorkoutRange] = []
    private(set) var sleepRanges: [SleepRange] = []
    private(set) var isHealthKitAuthorized = false
    private(set) var isLoadingHealthKit = false
    private(set) var healthKitErrorMessage: String?
    private(set) var calendarEventRanges: [CalendarEventRange] = []
    private(set) var isCalendarAuthorized = false
    private(set) var isLoadingCalendar = false
    private(set) var calendarErrorMessage: String?
    // 알림 임계값을 트리거한 실제 샘플의 시각(occurredAt)을 그대로 기록하므로, 차트 포인트의 date와
    // 나노초 단위 반올림 오차 정도만 있을 뿐 사실상 같은 시각이다 — 오차 허용치를 넉넉히 5분으로
    // 잡아도 정상 측정 간격(~2시간)보다 훨씬 좁아서 엉뚱한 포인트와 잘못 매칭될 일이 없다.
    private static let rmssdEventMatchTolerance: TimeInterval = 5 * 60
    private(set) var rmssdEvents: [RMSSDEventEntry] = []
    private var hasCheckedRMSSDEvents = false

    // 일별 모드는 간트 차트 대신 안정시 심박수 막대 차트를 보여준다 — 그날그날 뚝뚝 튀지 않는
    // 안정적인 지표라 하루 대표값(중앙값) 하나로 충분하다(rMSSD 일별 집계와 같은 방식).
    private(set) var wearableRestingHeartRatePointsDaily: [HRVPoint] = []
    // 오후 9시~다음 날 오전 10시 수면만 날짜별로 합산한 값. 낮잠은 시간 창 밖이라 제외된다.
    private(set) var nightlySleepPointsDaily: [DailySleepPoint] = []
    // 하루 동안 여러 건으로 누적 기록되는 값이라 날짜별로 합산한다(안정시 심박수처럼 중앙값을 쓰지 않음).
    private(set) var daylightPointsDaily: [DailyDaylightPoint] = []

    // 시간별 모드 아이콘 레인 전용 데이터 — HealthKit 윈도우 로딩과 무관하게(양이 많지 않아) 캘린더
    // 일정처럼 한 번에 전체 이력을 불러온다.
    private(set) var coffeeLogs: [CoffeeLogEntry] = []
    private(set) var lifeEvents: [LifeEventEntry] = []
    private var hasCheckedDailyMarkers = false

    func loadDailyMarkersIfNeeded() async {
        guard !hasCheckedDailyMarkers else { return }
        hasCheckedDailyMarkers = true
        await reloadDailyMarkers()
    }

    // pull-to-refresh처럼 강제로 다시 불러와야 할 때 씀. 세 데이터를 하나의 튜플로 await하면 그중
    // 하나만 실패해도 나머지 둘의 결과까지 통째로 버려지므로(예: 이벤트 서버가 잠깐 502를 내면
    // 이미 잘 불러온 커피/약복용까지 사라짐), 각각 독립적으로 실패를 흡수한다.
    func reloadDailyMarkers() async {
        async let coffees = try? CoffeeService.allCoffees()
        async let medicationLogsResult = try? MedicationService.allLogs()
        async let events = try? LifeEventService.allEvents()
        let (coffeeList, medicationLogList, eventList) = await (coffees, medicationLogsResult, events)

        if let coffeeList {
            coffeeLogs = coffeeList
        }
        if let medicationLogList {
            // 캘린더 배지와 같은 기준 — 아침약 10개를 챙겼어도 그건 "아침" 한 번이니, 시간대(날짜+
            // timing) 하나당 실제로 챙긴(taken) 시각(가장 이른 takenAt) 하나만 마커로 남긴다.
            // takenAt이 없는 로그는 이 시간축 위에 찍을 실제 시각이 없어 건너뛴다.
            let calendar = Calendar.current
            struct TimingKey: Hashable { let day: DateComponents; let timing: String? }
            var earliestByTiming: [TimingKey: (id: String, date: Date)] = [:]
            for log in medicationLogList where log.taken {
                guard let takenAt = log.takenAt.flatMap(DateKey.parseISODate) else { continue }
                let dayComponents = calendar.dateComponents([.year, .month, .day], from: takenAt)
                let key = TimingKey(day: dayComponents, timing: log.timing)
                let id = "medication-\(dayComponents.year ?? 0)-\(dayComponents.month ?? 0)-\(dayComponents.day ?? 0)-\(log.timing ?? "unknown")"
                if let existing = earliestByTiming[key], existing.date <= takenAt {
                    continue
                }
                earliestByTiming[key] = (id, takenAt)
            }
            medicationMarkers = earliestByTiming.values.map { $0 }
        }
        if let eventList {
            lifeEvents = eventList
        }
    }

    private var medicationMarkers: [(id: String, date: Date)] = []

    // 시간별 모드 아이콘 레인에 그릴 마커 전체 — 커피/약복용(시간대당 하나)/이벤트를 한 배열로 합친다.
    // id는 매번 새로 만들지 않고 원본 로그의 안정적인 값에서 뽑아서, 이 계산 프로퍼티가 스크롤 등으로
    // 자주 재평가돼도 SwiftUI가 마크를 불필요하게 다시 그리지 않게 한다.
    var dailyMarkers: [DailyMarker] {
        let coffeeMarkers = coffeeLogs.compactMap { entry -> DailyMarker? in
            guard let date = DateKey.parseISODate(entry.date) else { return nil }
            return DailyMarker(
                id: "coffee-\(entry.id)",
                date: date,
                kind: .coffee,
                title: entry.type ?? "커피",
                intensity: nil,
                description: entry.memo
            )
        }
        let medicationDailyMarkers = medicationMarkers.map { marker in
            DailyMarker(
                id: marker.id,
                date: marker.date,
                kind: .medication,
                title: "약 복용",
                intensity: nil,
                description: nil
            )
        }
        let eventMarkers = lifeEvents.compactMap { entry -> DailyMarker? in
            guard let date = DateKey.parseISODate(entry.date) else { return nil }
            let kind: DailyMarkerKind = entry.symptomType == nil ? .event : .symptom
            return DailyMarker(
                id: "event-\(entry.id)",
                date: date,
                kind: kind,
                title: entry.title,
                intensity: entry.intensity,
                description: entry.description
            )
        }
        return coffeeMarkers + medicationDailyMarkers + eventMarkers
    }

    // HealthKit(rMSSD 등)을 "전체 이력"이 아니라 화면에 보이는 구간의 loadWindowMultiplier배만
    // 불러온다 — rMSSD 계산이 원시 박동 시리즈를 전부 순회하는 무거운 연산이라, 데이터가 몇 년치
    // 쌓여도 매번 전부 다시 계산하지 않기 위함. 스크롤/핀치로 보이는 구간이 이 범위의 안전 여백
    // (prefetchMarginMultiplier배) 밖으로 나가려고 하면 새 위치를 중심으로 다시 불러온다.
    static let loadWindowMultiplier: Double = 5
    // 일별(기본 30일)부터는 5배를 적용하면 한 번에 150일 이상을 조회해 탭 전환이 버벅일 수 있다.
    // 30일 이상 범위는 2배만 미리 읽어 일별은 약 60일, 월별도 필요한 범위만 캐시한다.
    static let longRangeLoadWindowMultiplier: Double = 2
    private static let longRangeThreshold: TimeInterval = 30 * 24 * 60 * 60
    // 지금까지 불러온 HealthKit 데이터가 커버하는 실제 기간.
    private var loadedHealthKitRange: ClosedRange<Date>?
    private var isLoadingHealthKitWindow = false

    func hasLoadedHealthKitData(start: Date, end: Date) -> Bool {
        guard let loadedHealthKitRange else { return false }
        return start >= loadedHealthKitRange.lowerBound && end <= loadedHealthKitRange.upperBound
    }

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

    // 최근 30일 기준값은 스크롤 위치와 무관하게 항상 "오늘 기준"이어야 해서 별도로 조회한다.
    func loadRecentThirtyDayMedianIfNeeded() async {
        guard !hasCheckedRecentMedian else { return }
        hasCheckedRecentMedian = true

        do {
            try await HealthKitService.requestAuthorization()
            let baseline = try await RMSSDThreshold.fetchRecentThirtyDayBaseline()
            recentThirtyDayRMSSDMedian = baseline.overallMedian
            recentThirtyDayPeriodMedians = baseline.periodMedians
        } catch {
            healthKitErrorMessage = error.localizedDescription
            hasCheckedRecentMedian = false
        }
    }

    // 실제 수면 시작/종료와 정오를 경계로 보이는 구간을 잘라, 세 중앙값이 한 계단형 선으로 이어지게 한다.
    func recentMedianSegments(start: Date, end: Date) -> [RMSSDBaselineSegment] {
        guard let medians = recentThirtyDayPeriodMedians, end > start else { return [] }
        let calendar = Calendar.current
        var boundaries = [start, end]
        var day = calendar.startOfDay(for: start)
        while day < end {
            if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day), noon > start, noon < end {
                boundaries.append(noon)
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            if nextDay > start, nextDay < end { boundaries.append(nextDay) }
            day = nextDay
        }
        for range in sleepRanges where range.end > start && range.start < end {
            boundaries.append(max(range.start, start))
            boundaries.append(min(range.end, end))
        }
        let sorted = Array(Set(boundaries)).sorted()
        return zip(sorted, sorted.dropFirst()).compactMap { segmentStart, segmentEnd in
            let midpoint = segmentStart.addingTimeInterval(segmentEnd.timeIntervalSince(segmentStart) / 2)
            let isSleeping = sleepRanges.contains { midpoint >= $0.start && midpoint <= $0.end }
            let value = isSleeping
                ? medians.sleep
                : (calendar.component(.hour, from: midpoint) < 12 ? medians.morning : medians.afternoon)
            return value.map { RMSSDBaselineSegment(start: segmentStart, end: segmentEnd, value: $0) }
        }
    }

    func recentPeriodMedian(at date: Date) -> Double? {
        guard let medians = recentThirtyDayPeriodMedians else { return nil }
        if sleepRanges.contains(where: { date >= $0.start && date <= $0.end }) {
            return medians.sleep
        }
        return Calendar.current.component(.hour, from: date) < 12 ? medians.morning : medians.afternoon
    }

    // rMSSD 알림에 응답해 기록한 기분 — 스크롤 위치와 무관하게 항상 전체 이력을 불러온다(30일
    // 중앙값과 같은 이유로 windowed 로딩과 분리).
    func loadRMSSDEventsIfNeeded() async {
        guard !hasCheckedRMSSDEvents else { return }
        hasCheckedRMSSDEvents = true

        do {
            rmssdEvents = try await RMSSDEventService.allEvents()
        } catch {
            hasCheckedRMSSDEvents = false
        }
    }

    // pull-to-refresh처럼 강제로 다시 불러와야 할 때 씀 — 방금 알림에 응답해 새로 기록한 기분이
    // 있어도 hasCheckedRMSSDEvents가 이미 true라 loadRMSSDEventsIfNeeded는 아무것도 안 한다.
    func reloadRMSSDEvents() async {
        do {
            rmssdEvents = try await RMSSDEventService.allEvents()
        } catch {
            // best-effort — 실패해도 기존 값을 그대로 보여준다.
        }
    }

    // 시간별 라인 차트 포인트 하나(point.date == 실제 샘플 시각)에 매칭되는, 사용자가 실제로 응답해
    // 기분까지 남긴 rMSSD 이벤트가 있는지 찾는다. 있으면 그 포인트는 (원 테두리 대신) 다이아몬드로
    // 그려서 "알림에 응답한 순간"임을 표시한다.
    func rmssdEvent(near date: Date) -> RMSSDEventEntry? {
        rmssdEvents
            .compactMap { event -> (RMSSDEventEntry, TimeInterval)? in
                guard let occurredAt = DateKey.parseISODate(event.occurredAt) else { return nil }
                let distance = abs(occurredAt.timeIntervalSince(date))
                guard distance <= Self.rmssdEventMatchTolerance else { return nil }
                return (event, distance)
            }
            .min { $0.1 < $1.1 }?.0
    }

    // 일별 모드는 그 날의 대표값(중앙값)이라 point.date가 실제 샘플 시각이 아니라 그날 자정이다 —
    // 그래서 시간 차이가 아니라 "같은 날짜"인지로 매칭한다. 같은 날 이벤트가 여러 개면(드묾) 가장
    // 나중에 기록한 것을 보여준다.
    func rmssdEvent(onDay date: Date) -> RMSSDEventEntry? {
        let calendar = Calendar.current
        return rmssdEvents
            .compactMap { event -> (RMSSDEventEntry, Date)? in
                guard let occurredAt = DateKey.parseISODate(event.occurredAt),
                      calendar.isDate(occurredAt, inSameDayAs: date) else { return nil }
                return (event, occurredAt)
            }
            .max { $0.1 < $1.1 }?.0
    }

    // 지금 로딩 중일 때 새로 들어온 요청 — 버리지 않고 여기 남겨서, 지금 도는 로딩이 끝나면
    // 그 사이에 스크롤이 더 진행됐는지 확인해 최신 위치로 이어서 불러오게 한다(가장 최신 요청만
    // 의미가 있으므로 매번 덮어쓴다 — 중간 요청들을 다 큐잉할 필요는 없다).
    private var pendingWindowRequest: (start: Date, end: Date, force: Bool)?

    private func isWithinLoadedRange(start: Date, end: Date) -> Bool {
        guard let loadedHealthKitRange else { return false }
        let visibleWidth = end.timeIntervalSince(start)
        let loadedWidth = loadedHealthKitRange.upperBound.timeIntervalSince(loadedHealthKitRange.lowerBound)
        // 미리 읽은 여유 구간의 절반을 소비했을 때 다음 창을 준비한다. 로드 배수가 5배든 2배든
        // 같은 비율로 동작하며, 2배 월별 창이 항상 범위 밖으로 판정되는 문제를 피한다.
        let margin = max(0, (loadedWidth - visibleWidth) / 4)
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
        // 기존 차트 데이터가 있으면 뷰가 자체적으로 계속 차트를 보여주므로, 이 플래그를 모든 윈도우
        // 로딩에 켜도 전체 스피너로 바뀌지 않는다. 다만 모드 전환 직후 새 범위의 포인트가 아직 없을
        // 때는 잘못된 "원시 박동 데이터 없음" 문구 대신 로딩 상태를 정확히 표시할 수 있다.
        isLoadingHealthKit = true
        defer { isLoadingHealthKit = false }

        let visibleDomain = visibleEnd.timeIntervalSince(visibleStart)
        let center = visibleStart.addingTimeInterval(visibleDomain / 2)
        let multiplier = visibleDomain >= Self.longRangeThreshold
            ? Self.longRangeLoadWindowMultiplier
            : Self.loadWindowMultiplier
        let windowDomain = visibleDomain * multiplier
        let windowStart = center.addingTimeInterval(-windowDomain / 2)
        let windowEnd = center.addingTimeInterval(windowDomain / 2)

        do {
            try await HealthKitService.requestAuthorization()

            async let workouts = HealthKitService.fetchWorkoutRanges(start: windowStart, end: windowEnd)
            async let sleep = HealthKitService.fetchSleepStageSamples(start: windowStart, end: windowEnd)
            async let rmssdWindow = RMSSDLocalStore.shared.window(start: windowStart, end: windowEnd)
            async let sdnn = HealthKitService.fetchSDNNSamples(start: windowStart, end: windowEnd)
            async let restingHR = HealthKitService.fetchRestingHeartRateSamples(start: windowStart, end: windowEnd)
            async let daylight = HealthKitService.fetchTimeInDaylightSamples(start: windowStart, end: windowEnd)
            let (workoutRanges, sleepSamples, cachedRMSSDWindow, sdnnSamples, restingHRSamples, daylightSamples) = try await (
                workouts,
                sleep,
                rmssdWindow,
                sdnn,
                restingHR,
                daylight
            )
            try Task.checkCancellation()

            // 수동으로 입력한 운동 기록(백엔드)도 같은 레인에 합친다 — 실패해도 HealthKit 데이터
            // 표시는 막지 않도록 별도로 무시 가능한 에러 처리.
            let manualRanges = (try? await ExerciseService.allExercises()) ?? []
            try Task.checkCancellation()

            let rawRMSSDSamples = cachedRMSSDWindow.measurements
                .map { ($0.measuredAt, $0.value) }
                .sorted { $0.0 < $1.0 }
            wearableRMSSDPointsHourly = Self.segmentByGap(rawRMSSDSamples, gapThreshold: Self.hrvGapThresholdHourly)
            // 연속 날짜는 이어 그리되 두 측정일의 달력 날짜 차이가 2일 이상이면 선을 끊는다.
            // 초 단위 간격으로 판단하면 DST나 시각 정규화 차이의 영향을 받을 수 있어 날짜로 비교한다.
            let dailyRMSSD = cachedRMSSDWindow.summaries.compactMap { summary in
                summary.wholeDayMedian.map { (summary.date, $0) }
            }
            wearableRMSSDPointsDaily = Self.segmentDailyByDateGap(dailyRMSSD)
            let rawSDNNSamples = sdnnSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableSDNNPointsHourly = Self.segmentByGap(rawSDNNSamples, gapThreshold: Self.hrvGapThresholdHourly)
            wearableRMSSDMonthlyStats = Self.monthlyStats(
                dailySummaries: cachedRMSSDWindow.summaries,
                cachedSummaries: cachedRMSSDWindow.monthlySummaries
            )
            // 안정시 심박수는 하루에 하나(애플이 자체 계산)라 이미 대체로 하루 대표값이지만, 혹시
            // 같은 날 여러 개가 있어도 중앙값으로 합쳐 항상 막대 하나만 나오게 한다.
            let rawRestingHRSamples = restingHRSamples.map { ($0.date, $0.value) }.sorted { $0.0 < $1.0 }
            wearableRestingHeartRatePointsDaily = Self.segmentByGap(
                Self.dailyMedian(rawRestingHRSamples),
                gapThreshold: Self.hrvGapThresholdDaily
            )
            nightlySleepPointsDaily = Self.nightlySleepDurations(sleepSamples)
            daylightPointsDaily = Self.dailyDaylightSums(daylightSamples.map { ($0.date, $0.value) })
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
        } catch is CancellationError {
            // 탭이 바뀐 이전 범위의 결과는 오류로 표시하거나 화면 배열에 반영하지 않는다.
            return false
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

    private static func segmentDailyByDateGap(_ samples: [(Date, Double)]) -> [HRVPoint] {
        let calendar = Calendar.current
        var segment = 0
        var previousDate: Date?

        return samples.map { date, value in
            if let previousDate {
                let dayGap = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: previousDate),
                    to: calendar.startOfDay(for: date)
                ).day ?? 0
                if dayGap >= 2 {
                    segment += 1
                }
            }
            previousDate = date
            return HRVPoint(date: date, value: value, segment: segment)
        }
    }

    private static func dailyMedian(_ samples: [(Date, Double)]) -> [(Date, Double)] {
        HRVStatistics.dailyMedian(samples.map { (date: $0.0, value: $0.1) })
            .map { ($0.date, $0.value) }
    }

    // 각 수면 단계 샘플에서 그날 21:00~다음 날 10:00과 실제로 겹치는 부분만 합산한다.
    // 시작/종료 시각만 보고 세션 전체를 포함하면 21시 전이나 10시 이후 구간까지 섞일 수 있으므로
    // 경계에서 잘라 계산한다. 낮 시간 수면은 창과 겹치지 않아 자연스럽게 제외된다.
    private static func nightlySleepDurations(
        _ samples: [(start: Date, end: Date, stage: HealthKitService.SleepStage)]
    ) -> [DailySleepPoint] {
        let calendar = Calendar.current
        var durationByNight: [Date: TimeInterval] = [:]

        for sample in samples {
            let night = SleepAnalysisService.nightLabel(for: sample.start)
            guard
                let windowStart = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: night),
                let nextDay = calendar.date(byAdding: .day, value: 1, to: night),
                let windowEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay)
            else { continue }

            let overlapStart = max(sample.start, windowStart)
            let overlapEnd = min(sample.end, windowEnd)
            guard overlapEnd > overlapStart else { continue }
            durationByNight[calendar.startOfDay(for: night), default: 0] += overlapEnd.timeIntervalSince(overlapStart)
        }

        return durationByNight
            .map { DailySleepPoint(date: $0.key, hours: $0.value / 3_600) }
            .sorted { $0.date < $1.date }
    }

    // timeInDaylight은 걸음수처럼 하루 동안 여러 샘플로 누적 기록되므로, 안정시 심박수(중앙값)와
    // 달리 날짜별 합산이 맞다.
    private static func dailyDaylightSums(_ samples: [(Date, Double)]) -> [DailyDaylightPoint] {
        let calendar = Calendar.current
        var minutesByDay: [Date: Double] = [:]
        for (date, value) in samples {
            minutesByDay[calendar.startOfDay(for: date), default: 0] += value
        }
        return minutesByDay
            .map { DailyDaylightPoint(date: $0.key, minutes: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private static func monthlyStats(
        dailySummaries: [DailyRMSSDSummaryDTO],
        cachedSummaries: [MonthlyRMSSDSummaryDTO]
    ) -> [MonthlyHRVStat] {
        let calendar = Calendar.current
        let cachedMonthStarts = Set(cachedSummaries.map(\.monthStart))
        var liveGroups: [Date: [Double]] = [:]
        for summary in dailySummaries {
            guard let value = summary.wholeDayMedian,
                  let monthStart = calendar.dateInterval(of: .month, for: summary.date)?.start,
                  !cachedMonthStarts.contains(monthStart)
            else { continue }
            liveGroups[monthStart, default: []].append(value)
        }

        let cached = cachedSummaries.map {
            MonthlyHRVStat(
                monthStart: $0.monthStart,
                q1: $0.q1,
                median: $0.median,
                q3: $0.q3,
                cv: $0.coefficientOfVariation
            )
        }
        let live = liveGroups.map { monthStart, values in
            let quartiles = HRVStatistics.quartiles(values)
            return MonthlyHRVStat(
                monthStart: monthStart,
                q1: quartiles.q1,
                median: quartiles.median,
                q3: quartiles.q3,
                cv: HRVStatistics.coefficientOfVariation(values)
            )
        }
        return (cached + live)
            .sorted { $0.monthStart < $1.monthStart }
    }
}
