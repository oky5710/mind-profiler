import Foundation

// 사용자가 기록한 전체 기간의 생활 데이터와 일별 rMSSD 중앙값 사이의 관계를 계산한다.
// 보고서 기간과 독립적인 설정 도구라, 사용자가 분석 화면에 들어갔을 때만 전체 HealthKit 이력을 조회한다.
@MainActor
@Observable
final class CorrelationAnalysisViewModel {
    struct Finding: Identifiable {
        let variable: String
        let coefficient: Double?
        let strengthLabel: String?
        let sampleCount: Int

        var id: String { variable }
        var strength: Double { coefficient.map(abs) ?? -1 }
    }

    private static let minimumSleepDurationHours = 2.0

    private(set) var findings: [Finding] = []
    private(set) var isLoading = false
    private(set) var hasAnalyzed = false
    private(set) var errorMessage: String?

    func analyze() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await HealthKitService.requestAuthorization()

            async let rmssdTask = HealthKitService.fetchRMSSDSamples()
            async let sleepTask = HealthKitService.fetchSleepStageSamples()
            async let healthKitWorkoutsTask = HealthKitService.fetchWorkoutRanges()
            async let moodsTask = MoodService.allMoods()
            async let coffeesTask = CoffeeService.allCoffees()
            async let manualExercisesTask = ExerciseService.allExercises()

            let (rmssd, sleepSamples, healthKitWorkouts, moods, coffees, manualExercises) = try await (
                rmssdTask,
                sleepTask,
                healthKitWorkoutsTask,
                moodsTask,
                coffeesTask,
                manualExercisesTask
            )

            let workoutDates = healthKitWorkouts.map(\.start) + manualExercises.compactMap {
                DateKey.parseISODate($0.startedAt)
            }
            findings = Self.computeFindings(
                dailyRMSSD: HRVStatistics.dailyMedian(rmssd),
                sleepRanges: SleepAnalysisService.buildSleepRanges(sleepSamples),
                workoutDates: workoutDates,
                moods: Self.parseMoodEntries(moods),
                coffees: Self.parseCoffeeEntries(coffees)
            )
            hasAnalyzed = true
        } catch {
            findings = []
            hasAnalyzed = false
            errorMessage = error.localizedDescription
        }
    }

    private static func computeFindings(
        dailyRMSSD: [(date: Date, value: Double)],
        sleepRanges: [SleepRange],
        workoutDates: [Date],
        moods: [(date: Date, score: Int)],
        coffees: [(date: Date, count: Int)]
    ) -> [Finding] {
        let calendar = Calendar.current
        let rmssdByDay = Dictionary(
            uniqueKeysWithValues: dailyRMSSD.map { (calendar.startOfDay(for: $0.date), $0.value) }
        )

        let moodPairs: [(Double, Double)] = moods.compactMap { mood in
            guard let rmssd = rmssdByDay[calendar.startOfDay(for: mood.date)] else { return nil }
            return (Double(mood.score), rmssd)
        }
        let coffeePairs: [(Double, Double)] = coffees.compactMap { coffee in
            guard let rmssd = rmssdByDay[calendar.startOfDay(for: coffee.date)] else { return nil }
            return (Double(coffee.count), rmssd)
        }

        let exerciseDays = Set(workoutDates.map { calendar.startOfDay(for: $0) })
        let exercisePairs: [(Double, Double)] = rmssdByDay.compactMap { day, value in
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            return (exerciseDays.contains(previousDay) ? 1 : 0, value)
        }

        var sleepMetricsByDay: [Date: (duration: Double, weightedScore: Double)] = [:]
        for range in sleepRanges {
            let day = SleepAnalysisService.nightLabel(for: range.start)
            let duration = range.end.timeIntervalSince(range.start) / 3600
            let existing = sleepMetricsByDay[day] ?? (duration: 0, weightedScore: 0)
            sleepMetricsByDay[day] = (
                duration: existing.duration + duration,
                weightedScore: existing.weightedScore + Double(range.estimatedScore) * duration
            )
        }

        let eligibleSleepPairs: [(metrics: (duration: Double, weightedScore: Double), rmssd: Double)] =
            rmssdByDay.compactMap { day, value in
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
                      let metrics = sleepMetricsByDay[previousDay],
                      metrics.duration > minimumSleepDurationHours else { return nil }
                return (metrics, value)
            }
        let sleepDurationPairs = eligibleSleepPairs.map { ($0.metrics.duration, $0.rmssd) }
        let sleepScorePairs = eligibleSleepPairs.map {
            ($0.metrics.weightedScore / $0.metrics.duration, $0.rmssd)
        }

        return [
            finding("기분", pairs: moodPairs),
            finding("커피 잔 수", pairs: coffeePairs),
            finding("전날 운동", pairs: exercisePairs),
            finding("전날 수면시간", pairs: sleepDurationPairs),
            finding("전날 수면점수", pairs: sleepScorePairs)
        ]
        .sorted { $0.strength > $1.strength }
    }

    private static func finding(_ variable: String, pairs: [(Double, Double)]) -> Finding {
        let coefficient = HRVStatistics.pearsonCorrelation(pairs)
        return Finding(
            variable: variable,
            coefficient: coefficient,
            strengthLabel: coefficient.map { HRVStatistics.correlationStrengthLabel($0) },
            sampleCount: pairs.count
        )
    }

    private static let moodDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static func parseMoodEntries(_ entries: [MoodLogEntry]) -> [(date: Date, score: Int)] {
        entries.compactMap { entry in
            guard let dayKey = DateKey.dateOnlyString(fromISO: entry.date),
                  let date = moodDateFormatter.date(from: dayKey) else { return nil }
            return (date, entry.score)
        }
    }

    private static func parseCoffeeEntries(_ entries: [CoffeeLogEntry]) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for entry in entries {
            guard let date = DateKey.parseISODate(entry.date) else { continue }
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }
    }
}
