import Foundation

@MainActor
@Observable
final class UnsolvedCasesViewModel {
    private(set) var unsolvedCaseResults: [UnsolvedCaseResult] = []
    private(set) var isLoadingUnsolvedCases = false

    private var hasLoadedUnsolvedCases = false

    func loadUnsolvedCasesIfNeeded() async {
        guard !hasLoadedUnsolvedCases, !isLoadingUnsolvedCases else { return }
        isLoadingUnsolvedCases = true
        defer { isLoadingUnsolvedCases = false }

        do {
            try await HealthKitService.requestAuthorization()
            let calendar = Calendar.current
            let end = Date()
            let start = calendar.date(byAdding: .day, value: -LongTermCaseConfiguration.analysisDays, to: end) ?? end
            async let rmssdSummaryTask = RMSSDLocalStore.shared.dailySummaries(start: start, end: end)
            async let sleepTask = HealthKitService.fetchSleepStageSamples(start: start, end: end)
            async let healthWorkoutsTask = HealthKitService.fetchWorkoutRanges(start: start, end: end)
            async let coffeesTask: [CoffeeLogEntry]? = try? CoffeeService.allCoffees()
            async let manualWorkoutsTask: [ExerciseLogEntry]? = try? ExerciseService.allExercises()
            let (rmssdSummaries, sleepSamples, healthWorkouts, coffeeEntries, manualEntries) = try await (
                rmssdSummaryTask, sleepTask, healthWorkoutsTask, coffeesTask, manualWorkoutsTask
            )

            let sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)
            // 같은 밤이 긴 각성으로 여러 SleepRange로 나뉘어도 분석에서는 하루 한 건이어야 한다.
            let rangesByNight = Dictionary(grouping: sleepRanges) {
                calendar.startOfDay(for: SleepAnalysisService.nightLabel(for: $0.start))
            }
            let sleeps = rangesByNight.map { night, ranges in
                LongTermNightSleepRecord(
                    nightDate: night,
                    sleepMinutes: ranges.flatMap { $0.stageDurations.values }.reduce(0, +) / 60
                )
            }
            let coffees = (coffeeEntries ?? []).compactMap { entry -> LongTermCoffeeRecord? in
                guard let date = DateKey.parseISODate(entry.date), date >= start, date <= end else { return nil }
                return LongTermCoffeeRecord(date: date)
            }
            let healthWorkoutRecords = healthWorkouts.map {
                LongTermWorkoutRecord(start: $0.start, durationMinutes: $0.end.timeIntervalSince($0.start) / 60)
            }
            let manualWorkouts = (manualEntries ?? []).compactMap { entry -> LongTermWorkoutRecord? in
                guard let workoutStart = DateKey.parseISODate(entry.startedAt),
                      let workoutEnd = DateKey.parseISODate(entry.endedAt),
                      workoutStart >= start, workoutEnd > workoutStart else { return nil }
                return LongTermWorkoutRecord(start: workoutStart, durationMinutes: workoutEnd.timeIntervalSince(workoutStart) / 60)
            }
            let daily = rmssdSummaries.compactMap { summary in
                summary.wholeDayMedian.map { LongTermDailyRMSSD(date: summary.date, median: $0) }
            }
            let morning = rmssdSummaries.compactMap { summary in
                summary.morningMedian.map { LongTermDailyRMSSD(date: summary.date, median: $0) }
            }
            let commuteStatuses = await Self.fetchCommuteStatuses(start: start, end: end)

            unsolvedCaseResults = LongTermCaseAnalyzer.analyze(
                coffees: coffees,
                workouts: healthWorkoutRecords + manualWorkouts,
                sleeps: sleeps,
                morningRMSSD: morning,
                dailyRMSSD: daily,
                commuteStatusByDay: commuteStatuses
            )
            hasLoadedUnsolvedCases = true
        } catch {
            unsolvedCaseResults = []
        }
    }

    private static func fetchCommuteStatuses(start: Date, end: Date) async -> [Date: LongTermCommuteStatus] {
        let calendar = Calendar.current
        var statuses: [Date: LongTermCommuteStatus] = [:]
        var day = calendar.startOfDay(for: start)
        let finalDay = calendar.startOfDay(for: end)
        while day <= finalDay {
            let weekday = calendar.component(.weekday, from: day)
            statuses[day] = (weekday == 1 || weekday == 7) ? .nonWorkday : .workday
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        do {
            try await CalendarEventService.requestAuthorization()
            let events = await CalendarEventService.fetchEvents(start: start, end: end)
            for event in events {
                let isNonWorkday = event.category == .holiday
                    || (event.category == .vacation && event.isAllDay)
                guard isNonWorkday else { continue }

                var eventDay = calendar.startOfDay(for: max(event.start, start))
                // EventKit 종일 일정의 end는 마지막 날 다음 날 자정인 배타적 경계다.
                let effectiveEnd = event.isAllDay ? event.end.addingTimeInterval(-1) : event.end
                let lastDay = calendar.startOfDay(for: min(effectiveEnd, end))
                while eventDay <= lastDay {
                    statuses[eventDay] = .nonWorkday
                    guard let next = calendar.date(byAdding: .day, value: 1, to: eventDay) else { break }
                    eventDay = next
                }
            }
            return statuses
        } catch {
            // 캘린더 권한이 없어도 토·일요일은 비출근, 평일은 출근으로 분석한다.
            return statuses
        }
    }
}
