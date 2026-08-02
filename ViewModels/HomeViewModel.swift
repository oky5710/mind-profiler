import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var errorMessage: String?
    private(set) var briefingCaseType: BriefingCaseType?
    private(set) var recoveryScore: RecoveryScore?
    private(set) var briefingDate: Date?
    private(set) var briefingClues: [BriefingClue] = []
    private(set) var todayBriefingClues: [BriefingClue] = []

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

    func loadDailyBriefing() async {
        // Apple Watch → iPhone HealthKit 동기화는 앱을 연 뒤 완료될 수 있으므로 홈에 들어올 때마다
        // 최신 수면을 다시 읽는다. 동시에 여러 번 실행되는 것만 막는다.
        guard !isLoadingDailyBriefing else { return }
        isLoadingDailyBriefing = true
        defer { isLoadingDailyBriefing = false }

        do {
            try await HealthKitService.requestAuthorization()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let latestNight = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let fetchDayCount = DailyBriefingConfiguration.sleepBaselineNightCount
                + DailyBriefingConfiguration.sleepFetchBufferDays
            let fetchStart = calendar.date(byAdding: .day, value: -fetchDayCount, to: latestNight) ?? latestNight
            let fetchEnd = calendar.date(byAdding: .day, value: 2, to: today) ?? Date()

            async let sleepTask = HealthKitService.fetchSleepStageSamples(start: fetchStart, end: fetchEnd)
            async let timelineTask = HealthKitService.fetchSleepTimelineSamples(start: fetchStart, end: fetchEnd)
            async let rmssdTask = HealthKitService.fetchRMSSDSamples(start: fetchStart, end: fetchEnd)
            let (sleepSamples, timeline, rmssdSamples) = try await (sleepTask, timelineTask, rmssdTask)

            let ranges = SleepAnalysisService.buildSleepRanges(sleepSamples)
            let now = Date()
            let recentStart = calendar.date(byAdding: .day, value: -30, to: now) ?? fetchStart
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
            let todayNotes = ((try? await RMSSDEventService.allEvents()) ?? []).compactMap { entry -> (Date, String)? in
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

            guard let currentRange = ranges.last(where: {
                SleepAnalysisService.nightLabel(for: $0.start) <= latestNight
            }) else {
                clearDailyBriefing()
                return
            }
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
            async let noteEntriesTask: [RMSSDEventEntry]? = try? RMSSDEventService.allEvents()
            let (coffeeEntries, exerciseEntries, schedules, noteEntries) = await (
                coffeeEntriesTask,
                exerciseEntriesTask,
                schedulesTask,
                noteEntriesTask
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
            briefingDate = currentNight
            briefingClues = BriefingClueBuilder.build(from: input)
        } catch {
            // HealthKit의 일시적 조회 실패로 마지막 정상 브리핑이 화면에서 사라지지 않게 보존한다.
            // 다음 홈 진입 때 다시 조회하며, 정상 조회에서 데이터가 실제로 없을 때만 위 guard에서 비운다.
        }
    }

    private func clearDailyBriefing() {
        briefingCaseType = nil
        briefingDate = nil
        briefingClues = []
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
        let awakeIntervals = timeline
            .filter { $0.stage == .awake && $0.end > range.start && $0.start < range.end }
            .map { (start: max($0.start, range.start), end: min($0.end, range.end)) }
        let mergedAwake = SleepAnalysisService.mergeIntervals(awakeIntervals)
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
}
