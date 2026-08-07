import Foundation
import HealthKit

struct LatestRMSSDComparison {
    enum Status {
        case stable
        case good
        case overload

        var label: String {
            switch self {
            case .stable: "안정"
            case .good: "좋음"
            case .overload: "과부하"
            }
        }
    }

    let difference: Double
    let status: Status
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var errorMessage: String?
    private(set) var briefingCaseType: BriefingCaseType?
    private(set) var recoveryScore: RecoveryScore?
    private(set) var briefingDate: Date?
    private(set) var briefingClues: [BriefingClue] = []
    private(set) var todayBriefingClues: [BriefingClue] = []
    private(set) var dailySummaryHighlights: [DailySummaryHighlight] = []
    // "오늘 확보한 단서" 위 요약 수치 두 개. recoveryScore처럼 사건 판정 가드와 무관하게 구할 수 있는
    // 값이라 그 가드가 실패해도(previousNightSleepDuration은 전날 밤 수면 자체가 없을 때만 예외) 계속 보여준다.
    private(set) var latestRMSSDValue: Double?
    private(set) var latestRMSSDComparison: LatestRMSSDComparison?
    private(set) var previousNightSleepDuration: TimeInterval?

    private(set) var todayMoodScore: Int?
    private(set) var moodErrorMessage: String?
    private(set) var hasCheckedMood = false

    private(set) var todayCoffeeCount = 0
    private(set) var coffeeErrorMessage: String?

    private(set) var hasMorningMedicationTaken = false
    private(set) var hasBedtimeMedicationTaken = false
    private(set) var medicationErrorMessage: String?

    private var hasCheckedCoffee = false
    private var hasCheckedMedicationLogs = false
    private var isLoadingDailyBriefing = false
    // 로딩 도중 다른 날짜가 또 선택되면(주 스트립을 빠르게 스와이프/탭) 그 요청을 잃어버리지 않고
    // 기억해뒀다가, 지금 로드가 끝나는 즉시 이어서 그 날짜로 다시 로드한다 — 항상 마지막으로 선택한
    // 날짜가 최종적으로 반영된다.
    private var latestRequestedBriefingDate: Date?

    // hrvTerm: 연구자/관리자는 "rMSSD", 일반 사용자는 "HRV"(AuthViewModel.hrvTerm) — 이 뷰모델은
    // View가 아니라 environment에 직접 접근할 수 없어 호출부(HomeView)가 넘겨준다.
    func loadDailyBriefing(for selectedDate: Date = Date(), hrvTerm: String) async {
        latestRequestedBriefingDate = selectedDate
        guard !isLoadingDailyBriefing else { return }
        isLoadingDailyBriefing = true
        defer { isLoadingDailyBriefing = false }

        var dateToLoad = selectedDate
        while true {
            await performDailyBriefingLoad(for: dateToLoad, hrvTerm: hrvTerm)
            guard let latest = latestRequestedBriefingDate,
                  !Calendar.current.isDate(latest, inSameDayAs: dateToLoad)
            else { break }
            dateToLoad = latest
        }
    }

    private func performDailyBriefingLoad(for selectedDate: Date, hrvTerm: String) async {
        // Apple Watch → iPhone HealthKit 동기화는 앱을 연 뒤 완료될 수 있으므로 홈에 들어올 때마다
        // 최신 수면을 다시 읽는다.
        do {
            try await HealthKitService.requestAuthorization()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: selectedDate)
            // "사건 일자"는 회복 지수(recoveryScore, 최근 30일 데이터로 아래에서 계산)와 달리 이 함수
            // 아래쪽의 엄격한 조건(전날 밤 수면 일치·기준 밤 존재·중앙값 계산 성공)에 걸려 정상적으로
            // 실패할 수 있다 — 그 실패로 clearDailyBriefing이 호출돼도 헤더는 recoveryScore만으로도
            // 뜨므로, 사용자가 고른 날짜는 그 실패 여부와 무관하게 항상 먼저 반영해 둔다.
            briefingDate = today
            let latestNight = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let fetchDayCount = DailyBriefingConfiguration.sleepBaselineNightCount
                + DailyBriefingConfiguration.sleepFetchBufferDays
            let fetchStart = calendar.date(byAdding: .day, value: -fetchDayCount, to: latestNight) ?? latestNight
            let fetchEnd = calendar.date(byAdding: .day, value: 2, to: today) ?? Date()
            // 선택한 날짜가 오늘이면 지금 이 순간까지, 과거 날짜면 그날 23:59:59까지를 "그날 하루"의
            // 끝으로 본다 — 과거 날짜 전체를 다 포함하면서도 달력 날짜 판정(calendar.startOfDay)이
            // 다음 날로 밀리지 않게 한다.
            let now: Date = calendar.isDateInToday(selectedDate)
                ? Date()
                : (calendar.date(byAdding: .day, value: 1, to: today)
                    .flatMap { calendar.date(byAdding: .second, value: -1, to: $0) } ?? today)
            let recentStart = calendar.date(byAdding: .day, value: -30, to: now) ?? fetchStart

            async let sleepTask = HealthKitService.fetchSleepStageSamples(start: fetchStart, end: fetchEnd)
            async let timelineTask = HealthKitService.fetchSleepTimelineSamples(start: fetchStart, end: fetchEnd)
            async let rmssdTask = HealthKitService.fetchRMSSDSamples(start: fetchStart, end: fetchEnd)
            // 오전 회복(기상 후 2시간)·심박수·하루 rMSSD·운동 시간 지표를 위해 추가로 조회한다.
            async let heartRateTask = HealthKitService.fetchHeartRateSamples(start: fetchStart, end: fetchEnd)
            async let dailyRMSSDSummaryTask = RMSSDLocalStore.shared.dailySummaries(start: recentStart, end: now)
            async let healthWorkoutsForSummaryTask = HealthKitService.fetchWorkoutRanges(start: recentStart, end: now)
            // 뒤에서 hrvNotes를 만들 때도 이 이벤트 목록이 다시 필요한데, 매번 다시 가져오지 않고
            // 여기서 한 번만 가져와서 재사용한다(오늘 것만 거르는 todayNotes와 evidence 구간만 거르는
            // hrvNotes 둘 다 이 배열을 필터링만 다르게 한 결과다).
            async let noteEntriesTask: [RMSSDEventEntry]? = try? RMSSDEventService.allEvents()
            let (sleepSamples, timeline, rmssdSamples, heartRateSamples, dailyRMSSDSummaries, healthWorkoutsForSummary, noteEntries) = try await (
                sleepTask, timelineTask, rmssdTask, heartRateTask, dailyRMSSDSummaryTask, healthWorkoutsForSummaryTask, noteEntriesTask
            )

            let ranges = SleepAnalysisService.buildSleepRanges(sleepSamples)
            let recentRMSSD = rmssdSamples.filter { $0.date >= recentStart && $0.date <= now }
            let recentSleepRanges = ranges.filter { $0.end >= recentStart && $0.start <= now }
            let recentBaseline = RMSSDThreshold.makeRecentBaseline(
                samples: recentRMSSD,
                sleepRanges: recentSleepRanges
            )
            recoveryScore = RecoveryScoreBuilder.build(
                samples: recentRMSSD,
                sleepRanges: recentSleepRanges,
                day: now
            )
            let latestRMSSDSample = rmssdSamples
                .filter { $0.date <= now }
                .max { $0.date < $1.date }
            latestRMSSDValue = latestRMSSDSample?.value
            latestRMSSDComparison = latestRMSSDSample.flatMap {
                Self.latestRMSSDComparison(
                    for: $0,
                    samples: recentRMSSD,
                    sleepRanges: recentSleepRanges,
                    calendar: calendar
                )
            }
            let todayNotes = (noteEntries ?? []).compactMap { entry -> (Date, String)? in
                guard let date = DateKey.parseISODate(entry.occurredAt),
                      calendar.isDate(date, inSameDayAs: now),
                      let note = entry.note else { return nil }
                return (date, note)
            }
            todayBriefingClues = TodayBriefingClueBuilder.build(
                samples: rmssdSamples,
                baseline: recentBaseline,
                notes: todayNotes,
                day: now
            )

            // 선택한 날짜 바로 전날 밤과 정확히 일치하는 수면만 사건으로 삼는다. 예전엔 이전
            // 밤까지 넘어가며 찾았는데(<=), 그러면 그 밤 수면 기록이 없을 때 훨씬 이전 날짜의
            // 수면이 "사건 일자"로 표시돼 사용자가 고른 날짜와 어긋나 보였다.
            guard let currentRange = ranges.last(where: {
                SleepAnalysisService.nightLabel(for: $0.start) == latestNight
            }) else {
                // 그 밤 수면 기록 자체가 없으면 전날 수면시간도 진짜로 없는 것이므로 비운다 —
                // clearDailyBriefing()은 이 값을 건드리지 않아서(아래 참고) 여기서 직접 비운다.
                previousNightSleepDuration = nil
                clearDailyBriefing()
                return
            }
            // 사건 판정용 기준 밤이나 중앙값 계산이 이후에 실패해도(clearDailyBriefing 호출) 전날 밤
            // 수면 자체는 이미 확인됐으므로 계속 보여준다.
            previousNightSleepDuration = currentRange.stageDurations.values.reduce(0, +)
            let currentNight = SleepAnalysisService.nightLabel(for: currentRange.start)

            let previousRanges = ranges
                .filter { SleepAnalysisService.nightLabel(for: $0.start) < currentNight }
                .suffix(DailyBriefingConfiguration.sleepBaselineNightCount)
            guard !previousRanges.isEmpty else {
                clearDailyBriefing()
                return
            }

            let current = Self.briefingNight(range: currentRange, timeline: timeline, rmssd: rmssdSamples)
            let previous = previousRanges.map {
                Self.briefingNight(range: $0, timeline: timeline, rmssd: rmssdSamples)
            }
            guard
                let sleepDurationMedian = previous.map(\.sleepDuration).median,
                let awakeDurationMedian = previous.map(\.awakeDuration).median,
                let awakeRatioMedian = previous.map(\.awakeRatio).median,
                let longestContinuousSleepMedian = previous.map(\.longestContinuousSleep).median,
                let currentRMSSD = current.rmssd,
                let rmssdMedian = previous.compactMap(\.rmssd).median,
                rmssdMedian > 0
            else {
                clearDailyBriefing()
                return
            }

            let evidenceStart = calendar.date(
                byAdding: .day,
                value: -(max(DailyBriefingConfiguration.evidenceLookbackDays, 1) - 1),
                to: currentNight
            ) ?? currentNight
            let behaviorEnd = currentRange.start
            let observationEnd = currentRange.end

            // 부가 기록 하나가 실패해도 수면·HRV 단서는 계속 만든다.
            async let coffeeEntriesTask: [CoffeeLogEntry]? = try? CoffeeService.allCoffees()
            async let exerciseEntriesTask: [ExerciseLogEntry]? = try? ExerciseService.allExercises()
            async let schedulesTask = Self.fetchSchedules(start: evidenceStart, end: behaviorEnd)
            let (coffeeEntries, exerciseEntries, schedules) = await (
                coffeeEntriesTask,
                exerciseEntriesTask,
                schedulesTask
            )

            let coffees = (coffeeEntries ?? []).compactMap { entry -> BriefingCoffeeRecord? in
                guard let date = DateKey.parseISODate(entry.date), date >= evidenceStart, date < behaviorEnd else {
                    return nil
                }
                return BriefingCoffeeRecord(date: date)
            }
            let workouts = (exerciseEntries ?? []).compactMap { entry -> BriefingWorkoutRecord? in
                guard
                    let start = DateKey.parseISODate(entry.startedAt),
                    let end = DateKey.parseISODate(entry.endedAt),
                    start >= evidenceStart,
                    start < behaviorEnd,
                    end > start
                else { return nil }
                return BriefingWorkoutRecord(
                    start: start,
                    durationMinutes: end.timeIntervalSince(start) / 60,
                    intensity: entry.intensity.map(Double.init)
                )
            }
            let hrvNotes = (noteEntries ?? []).compactMap { entry -> BriefingHRVNote? in
                guard
                    let date = DateKey.parseISODate(entry.occurredAt),
                    date >= evidenceStart,
                    date <= observationEnd,
                    let note = entry.note,
                    let direction = RMSSDThresholdDirection(rawValue: entry.direction)
                else { return nil }
                return BriefingHRVNote(
                    date: date,
                    note: note,
                    direction: direction
                )
            }
            let priorRMSSDValues = previous.compactMap(\.rmssd)
            let rmssdPercentile = priorRMSSDValues.isEmpty ? nil :
                Double(priorRMSSDValues.filter { $0 <= currentRMSSD }.count) / Double(priorRMSSDValues.count) * 100
            let rmssdChangePercent = Self.percentChange(current: currentRMSSD, baseline: rmssdMedian)

            let input = DailyBriefingInput(
                sleepDurationChangeMinutes: (current.sleepDuration - sleepDurationMedian) / 60,
                awakeDurationChangeMinutes: (current.awakeDuration - awakeDurationMedian) / 60,
                awakeRatioChangePercent: Self.percentChange(
                    current: current.awakeRatio,
                    baseline: awakeRatioMedian
                ),
                longestContinuousSleepChangeMinutes:
                    (current.longestContinuousSleep - longestContinuousSleepMedian) / 60,
                rmssdValue: currentRMSSD,
                rmssdChangePercent: rmssdChangePercent,
                rmssdPercentile30Days: rmssdPercentile,
                coffees: coffees,
                workouts: workouts,
                schedules: schedules,
                hrvNotes: hrvNotes
            )
            let caseType = BriefingCaseDetector.detect(from: input)
            briefingCaseType = caseType
            briefingClues = BriefingClueBuilder.build(from: input, hrvTerm: hrvTerm)

            dailySummaryHighlights = DailySummaryBuilder.build(from: Self.dailySummaryInput(
                current: current,
                previous: previous,
                currentRange: currentRange,
                previousRanges: Array(previousRanges),
                sleepDurationMedian: sleepDurationMedian,
                awakeRatioMedian: awakeRatioMedian,
                rmssdMedian: rmssdMedian,
                heartRateSamples: heartRateSamples,
                rmssdSamples: rmssdSamples,
                dailyRMSSDSummaries: dailyRMSSDSummaries,
                healthWorkouts: healthWorkoutsForSummary,
                manualExercises: exerciseEntries ?? [],
                recentStart: recentStart,
                now: now,
                calendar: calendar
            ))
        } catch {
            // HealthKit의 일시적 조회 실패로 마지막 정상 브리핑이 화면에서 사라지지 않게 보존한다.
            // 다음 홈 진입 때 다시 조회하며, 정상 조회에서 데이터가 실제로 없을 때만 위 guard에서 비운다.
        }
    }

    // briefingDate는 여기서 지우지 않는다 — 선택한 날짜를 항상 그대로 보여주고, 사건 브리핑
    // 자체(단서·신호)만 조사 근거 부족으로 비운다(위 performDailyBriefingLoad의 briefingDate 주석 참고).
    private func clearDailyBriefing() {
        briefingCaseType = nil
        briefingClues = []
        dailySummaryHighlights = []
    }

    // 가장 최근 측정과 같은 시간대(수면 중/비수면 오전/비수면 오후)의 이전 30일 값만 비교한다.
    // 오늘 값은 "평소" 분포를 움직이지 않도록 기준에서 제외한다.
    private static func latestRMSSDComparison(
        for latest: (date: Date, value: Double),
        samples: [(date: Date, value: Double)],
        sleepRanges: [SleepRange],
        calendar: Calendar
    ) -> LatestRMSSDComparison? {
        let latestIsSleeping = sleepRanges.contains { latest.date >= $0.start && latest.date <= $0.end }
        let latestIsMorning = !latestIsSleeping && calendar.component(.hour, from: latest.date) < 12
        let latestDay = calendar.startOfDay(for: latest.date)

        let baselineValues = samples.compactMap { sample -> Double? in
            guard sample.date < latestDay else { return nil }
            let isSleeping = sleepRanges.contains { sample.date >= $0.start && sample.date <= $0.end }
            if latestIsSleeping { return isSleeping ? sample.value : nil }
            guard !isSleeping else { return nil }
            let isMorning = calendar.component(.hour, from: sample.date) < 12
            return isMorning == latestIsMorning ? sample.value : nil
        }
        guard baselineValues.count >= 2 else { return nil }

        let median = HRVStatistics.median(baselineValues)
        let standardDeviation = HRVStatistics.standardDeviation(baselineValues)
        let difference = latest.value - median
        let status: LatestRMSSDComparison.Status
        if difference > standardDeviation {
            status = .good
        } else if difference < -standardDeviation {
            status = .overload
        } else {
            status = .stable
        }
        return LatestRMSSDComparison(difference: difference, status: status)
    }

    func loadTodayMoodIfNeeded() async {
        guard !hasCheckedMood else { return }
        hasCheckedMood = true

        do {
            todayMoodScore = try await MoodService.todayMood()?.score
        } catch {
            moodErrorMessage = error.localizedDescription
            // 실패하면 "확인함" 표시를 되돌려서, 다음에 홈 탭에 다시 들어왔을 때(onAppear) 재시도된다 —
            // 안 그러면 이 뷰모델이 살아있는 한(탭을 벗어났다 돌아와도) 영영 다시 시도하지 않는다.
            hasCheckedMood = false
        }
    }

    func logMood(score: Int) async {
        moodErrorMessage = nil
        do {
            try await MoodService.logTodayMood(score: score)
            todayMoodScore = score
        } catch {
            moodErrorMessage = error.localizedDescription
        }
    }

    func loadTodayCoffeeCountIfNeeded() async {
        guard !hasCheckedCoffee else { return }
        hasCheckedCoffee = true

        do {
            todayCoffeeCount = try await CoffeeService.todayCount()
        } catch {
            coffeeErrorMessage = error.localizedDescription
            hasCheckedCoffee = false
        }
    }

    func logCoffee() async {
        coffeeErrorMessage = nil
        do {
            try await CoffeeService.logQuickCoffee()
            todayCoffeeCount += 1
        } catch {
            coffeeErrorMessage = error.localizedDescription
        }
    }

    func loadTodayMedicationLogsIfNeeded() async {
        guard !hasCheckedMedicationLogs else { return }
        hasCheckedMedicationLogs = true
        if !(await refreshTodayMedicationLogs()) {
            hasCheckedMedicationLogs = false
        }
    }

    // mind-record 웹의 홈 화면 퀵버튼(EntryScreen.tsx)과 동일하게 아침/취침만 지원한다.
    func logMedicationQuick(_ timing: MedicationTiming) async {
        medicationErrorMessage = nil
        do {
            let result = try await MedicationService.logTiming(timing, date: Date())
            // 퀵로그는 그 시간대로 등록된 약 전부를 처리하는 거라, 등록된 약이 없으면 호출은
            // 성공해도 로그가 하나도 안 생긴다 — 체크마크가 안 뜨는 게 버그가 아니라 이 경우라는 걸
            // 안내한다(그 전까진 아무 피드백 없이 조용히 실패하는 것처럼 보였다).
            if result.isEmpty {
                medicationErrorMessage = "\(timing.label)에 복용하도록 등록된 약이 없어요. 캘린더에서 약을 등록해보세요."
            } else {
                // 이 시간대로 알림을 걸어뒀다면, 다음 정기 재동기화를 기다리지 않고 오늘 자 알림을
                // 바로 취소한다.
                ReminderNotificationService.shared.cancelTodayOccurrences(forTiming: timing)
            }
            await refreshTodayMedicationLogs()
        } catch {
            medicationErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func refreshTodayMedicationLogs() async -> Bool {
        do {
            let logs = try await MedicationService.logs(on: Date())
            hasMorningMedicationTaken = logs.contains { $0.timing == MedicationTiming.morning.rawValue && $0.taken }
            hasBedtimeMedicationTaken = logs.contains { $0.timing == MedicationTiming.bedtime.rawValue && $0.taken }
            return true
        } catch {
            medicationErrorMessage = error.localizedDescription
            return false
        }
    }

    private struct BriefingNight {
        let sleepDuration: TimeInterval
        let awakeDuration: TimeInterval
        let awakeRatio: Double
        let longestContinuousSleep: TimeInterval
        let rmssd: Double?
    }

    private static func briefingNight(
        range: SleepRange,
        timeline: [(start: Date, end: Date, stage: HealthKitService.SleepTimelineStage)],
        rmssd: [(date: Date, value: Double)]
    ) -> BriefingNight {
        let mergedAwake = SleepAnalysisService.awakeIntervals(within: range, timeline: timeline)
        let windowDuration = max(0, range.end.timeIntervalSince(range.start))
        let awakeDuration = mergedAwake.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }

        var longestContinuousSleep: TimeInterval = 0
        var cursor = range.start
        for awake in mergedAwake {
            longestContinuousSleep = max(longestContinuousSleep, awake.start.timeIntervalSince(cursor))
            cursor = max(cursor, awake.end)
        }
        longestContinuousSleep = max(longestContinuousSleep, range.end.timeIntervalSince(cursor))

        return BriefingNight(
            sleepDuration: range.stageDurations.values.reduce(0, +),
            awakeDuration: awakeDuration,
            awakeRatio: windowDuration > 0 ? awakeDuration / windowDuration : 0,
            longestContinuousSleep: max(0, longestContinuousSleep),
            rmssd: rmssd
                .filter { $0.date >= range.start && $0.date <= range.end }
                .map(\.value)
                .median
        )
    }

    private static func fetchSchedules(
        start: Date,
        end: Date
    ) async -> [BriefingScheduleRecord] {
        do {
            try await CalendarEventService.requestAuthorization()
            return await CalendarEventService.fetchEvents(start: start, end: end).compactMap { event in
                let clippedStart = max(event.start, start)
                let clippedEnd = min(event.end, end)
                guard clippedEnd > clippedStart else { return nil }
                return BriefingScheduleRecord(
                    start: clippedStart,
                    end: clippedEnd
                )
            }
        } catch {
            return []
        }
    }

    private static func percentChange(current: Double, baseline: Double) -> Double {
        guard baseline != 0 else {
            if current == 0 { return 0 }
            return current > 0 ? .infinity : -.infinity
        }
        return ((current - baseline) / baseline) * 100
    }

    // "수사 기록하기" 위에 보여줄 오늘 하루 요약 문구(DailySummaryBuilder)에 필요한 변화율을 계산한다.
    // 운동 강도 지표는 제외하기로 해서 여기 포함하지 않는다.
    private static func dailySummaryInput(
        current: BriefingNight,
        previous: [BriefingNight],
        currentRange: SleepRange,
        previousRanges: [SleepRange],
        sleepDurationMedian: Double,
        awakeRatioMedian: Double,
        rmssdMedian: Double,
        heartRateSamples: [(date: Date, value: Double)],
        rmssdSamples: [(date: Date, value: Double)],
        dailyRMSSDSummaries: [DailyRMSSDSummaryDTO],
        healthWorkouts: [(start: Date, end: Date, activityType: HKWorkoutActivityType, energyBurnedKcal: Double?, distanceMeters: Double?)],
        manualExercises: [ExerciseLogEntry],
        recentStart: Date,
        now: Date,
        calendar: Calendar
    ) -> DailySummaryInput {
        // 수면 시간: 2시간 미만인 밤(낮잠 등)은 오늘/기준 양쪽에서 제외한다.
        let minimumSeconds = DailySummaryConfiguration.minimumSleepDurationMinutes * 60
        let sleepDurationChangePercent: Double? = current.sleepDuration >= minimumSeconds
            ? previous.map(\.sleepDuration).filter { $0 >= minimumSeconds }.median
                .map { percentChange(current: current.sleepDuration, baseline: $0) }
            : nil

        let sleepRecoveryRMSSDChangePercent: Double? = current.rmssd.flatMap { currentValue in
            previous.compactMap(\.rmssd).median.map { percentChange(current: currentValue, baseline: $0) }
        }

        let awakeRatioChangePercent = percentChange(current: current.awakeRatio, baseline: awakeRatioMedian)

        // 취침 시각: 자정을 넘나드는 비교를 위해 정오 기준으로 밀어서(분 단위) 비교한다.
        let currentBedtimeMinutes = SleepAnalysisService.bedtimeMinutesSinceNoon(currentRange.start)
        let bedtimeChangeMinutes = previousRanges
            .map { SleepAnalysisService.bedtimeMinutesSinceNoon($0.start) }
            .median
            .map { currentBedtimeMinutes - $0 }

        // 휴식 심박수: 수면 구간 내 평균(median이 아니라 평균) 심박수.
        func averageHeartRate(in range: SleepRange) -> Double? {
            let values = heartRateSamples.filter { $0.date >= range.start && $0.date <= range.end }.map(\.value)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        let restingHeartRateChangePercent: Double? = averageHeartRate(in: currentRange).flatMap { currentValue in
            previousRanges.compactMap(averageHeartRate).median.map { percentChange(current: currentValue, baseline: $0) }
        }

        // 하루 rMSSD: 오늘의 하루 중앙값 vs 최근 30일(오늘 제외) 하루 중앙값들의 중앙값.
        let todayKey = calendar.startOfDay(for: now)
        let todayDailyRMSSD = dailyRMSSDSummaries
            .first { calendar.isDate($0.date, inSameDayAs: todayKey) }?
            .wholeDayMedian
        let dailyRMSSDChangePercent: Double? = todayDailyRMSSD.flatMap { currentValue in
            dailyRMSSDSummaries
                .filter { !calendar.isDate($0.date, inSameDayAs: todayKey) }
                .compactMap(\.wholeDayMedian)
                .median
                .map { percentChange(current: currentValue, baseline: $0) }
        }

        // 운동 시간: 오늘 총 운동 시간(HealthKit 운동 + 수동 기록) vs 최근 30일(오늘 제외) 일별 총합의 중앙값.
        var exerciseMinutesByDay: [Date: Double] = [:]
        for workout in healthWorkouts {
            let day = calendar.startOfDay(for: workout.start)
            exerciseMinutesByDay[day, default: 0] += workout.end.timeIntervalSince(workout.start) / 60
        }
        for entry in manualExercises {
            guard let entryStart = DateKey.parseISODate(entry.startedAt),
                  let entryEnd = DateKey.parseISODate(entry.endedAt),
                  entryEnd > entryStart,
                  entryStart >= recentStart, entryStart <= now
            else { continue }
            let day = calendar.startOfDay(for: entryStart)
            exerciseMinutesByDay[day, default: 0] += entryEnd.timeIntervalSince(entryStart) / 60
        }
        let todayExerciseMinutes = exerciseMinutesByDay[todayKey] ?? 0
        let exerciseDurationChangePercent = exerciseMinutesByDay
            .filter { $0.key != todayKey }
            .map(\.value)
            .median
            .map { percentChange(current: todayExerciseMinutes, baseline: $0) }
        // 오늘이면 아직 운동할 시간이 남아있으니 지정한 시각 이후에만 "적었다"고 말한다. 지난
        // 날짜는 now가 그날 23:59:59이라 항상 이 시각을 넘긴다.
        let canShowLowActivityMessage = calendar.component(.hour, from: now)
            >= DailySummaryConfiguration.lowActivityMessageEarliestHour

        // 오전 회복(기상 후 2시간 rMSSD): 오늘 기상 시각 이후 2시간 vs 최근 30일 같은 구간 중앙값들의 중앙값.
        func morningRecoveryRMSSD(wakeTime: Date) -> Double? {
            let window = wakeTime...wakeTime.addingTimeInterval(2 * 60 * 60)
            return rmssdSamples.filter { window.contains($0.date) }.map(\.value).median
        }
        let morningRecoveryChangePercent: Double? = morningRecoveryRMSSD(wakeTime: currentRange.end).flatMap { currentValue in
            previousRanges
                .compactMap { morningRecoveryRMSSD(wakeTime: $0.end) }
                .median
                .map { percentChange(current: currentValue, baseline: $0) }
        }

        return DailySummaryInput(
            sleepDurationChangePercent: sleepDurationChangePercent,
            sleepRecoveryRMSSDChangePercent: sleepRecoveryRMSSDChangePercent,
            awakeRatioChangePercent: awakeRatioChangePercent,
            bedtimeChangeMinutes: bedtimeChangeMinutes,
            restingHeartRateChangePercent: restingHeartRateChangePercent,
            dailyRMSSDChangePercent: dailyRMSSDChangePercent,
            exerciseDurationChangePercent: exerciseDurationChangePercent,
            canShowLowActivityMessage: canShowLowActivityMessage,
            morningRecoveryChangePercent: morningRecoveryChangePercent
        )
    }
}
