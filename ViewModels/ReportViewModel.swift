import Foundation
import HealthKit

// 정신과 진료용 요약 보고서 — 이전 진료일부터 이번 진료일까지 기간을 골라 "분석"을 누르면
// 그 기간의 수면/rMSSD/SDNN 비교/기분·운동·커피 상관관계를 한 번에 계산해서 보여준다.
@MainActor
@Observable
final class ReportViewModel {
    struct RMSSDLowestFindings {
        // 일별 대표값(중앙값) 중 가장 낮은 날.
        let lowestDailyDate: Date?
        // 일별 대표값을 요일별로 평균 냈을 때 가장 낮은 요일 (1=일요일 ... 7=토요일).
        let lowestAverageWeekday: Int?
        // 날짜별로 그 날의 최저 1시간 버킷(0~23시)을 구한 뒤, 여러 날에 걸쳐 가장 자주
        // "그날의 최저"로 뽑힌 시간대(최빈값).
        let mostFrequentLowestHour: Int?
        // lowestDailyDate 전날/당일 수면 시간과 그날 캘린더 일정 — 화면에서 실제 날짜와 함께
        // 각각 한 줄씩 표시하도록 값 자체를 구조화해서 넘긴다(문자열로 미리 합쳐두지 않음).
        let lowestDayContext: LowestDayContext?
    }

    struct LowestDayContext {
        let previousNightDuration: TimeInterval?
        let sameNightDuration: TimeInterval?
        let eventTitles: [String]
    }

    // rMSSD가 낮았던 날 상위 N개를 표로 보여주기 위한 한 행 — 전날 수면/전날 운동은 회복에
    // 영향을 주는 "그 전"의 요인, 스케줄은 그날 자체에 있었던 일정(원인 쪽에 가깝다는 가정).
    struct RMSSDLowestDayRow: Identifiable {
        let date: Date
        let rmssd: Double
        let previousNightSleepDuration: TimeInterval?
        let scheduleTitles: [String]
        let previousDayExerciseSummary: String?
        var id: Date { date }
    }

    struct SDNNRMSSDDifference: Identifiable {
        let id = UUID()
        let date: Date
        let sdnn: Double
        let rmssd: Double
        var difference: Double { abs(sdnn - rmssd) }
    }

    // 변동계수(CV) = 표준편차 ÷ 평균 × 100 — rMSSD 기준.
    struct CVFindings {
        // 기간 내 모든 원시(시간별) rMSSD 샘플 분포로 계산한 전체 변동계수(%).
        let overallCV: Double
        let dailyPoints: [CVDailyPoint]
    }

    struct CVDailyPoint: Identifiable {
        let date: Date
        // 그날 원시 샘플들의 평균 — 라인차트로 그린다.
        let mean: Double
        // 그날을 포함한 이전 7일 원시 샘플 전체의 표준편차로 만든 밴드(평균 ± 표준편차).
        let lowerBand: Double
        let upperBand: Double
        var id: Date { date }
    }

    struct CorrelationFindings {
        // 기분 점수 vs 그날 rMSSD 중앙값의 Pearson 상관계수.
        let moodRMSSDCorrelation: Double?
        // 그날 커피 잔 수 vs rMSSD 중앙값의 Pearson 상관계수.
        let coffeeRMSSDCorrelation: Double?
        // 운동한 날 vs 안 한 날의 평균 rMSSD 비교 (상관계수보다 "그날 운동을 했는지" 자체가
        // 이진값이라 두 그룹 평균 비교가 더 읽기 쉽다).
        let exerciseDayAverageRMSSD: Double?
        let restDayAverageRMSSD: Double?
        // 운동 여부(0/1)와 rMSSD의 점-이연 상관계수 — 위 평균 비교는 텍스트 설명용이고, 이 값은
        // 기분/커피와 같은 기준(|r|)으로 정렬하기 위한 것.
        let exerciseRMSSDCorrelation: Double?
    }

    // 선택 기간 동안의 안정시 심박수/SDNN/rMSSD 원시 샘플 분포 중앙값 — 각각 다른 HealthKit 소스에서
    // 온 값이라 하나라도 없을 수 있다(예: rMSSD 계산용 원시 박동 시리즈가 없는 기기/기간).
    struct VitalMedians {
        let restingHeartRate: Double?
        let sdnn: Double?
        let rmssd: Double?
    }

    var previousVisitDate: Date
    var thisVisitDate: Date

    private(set) var isAnalyzing = false
    private(set) var errorMessage: String?
    private(set) var hasAnalyzed = false

    private(set) var sleepRanges: [SleepRange] = []
    private(set) var averageSleepDuration: TimeInterval?
    private(set) var averageSleepScore: Double?
    private(set) var cvFindings: CVFindings?
    private(set) var rmssdFindings: RMSSDLowestFindings?
    private(set) var topSDNNRMSSDDifferences: [SDNNRMSSDDifference] = []
    private(set) var correlationFindings: CorrelationFindings?
    private(set) var vitalMedians: VitalMedians?
    private(set) var rmssdLowestDayRows: [RMSSDLowestDayRow] = []

    init() {
        let now = Date()
        thisVisitDate = now
        previousVisitDate = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
    }

    func analyze() async {
        isAnalyzing = true
        errorMessage = nil
        hasAnalyzed = false
        defer { isAnalyzing = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: previousVisitDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: thisVisitDate)) else {
            errorMessage = "날짜 범위를 계산할 수 없어요."
            return
        }

        do {
            try await HealthKitService.requestAuthorization()

            async let sleepSamplesTask = HealthKitService.fetchSleepStageSamples()
            async let rmssdSamplesTask = HealthKitService.fetchRMSSDSamples()
            async let sdnnSamplesTask = HealthKitService.fetchSDNNSamples()
            async let restingHeartRateSamplesTask = HealthKitService.fetchRestingHeartRateSamples()
            async let workoutsTask = HealthKitService.fetchWorkoutRanges()
            async let moodsTask = MoodService.allMoods()
            async let coffeesTask = CoffeeService.allCoffees()
            async let calendarEventsTask = Self.fetchCalendarEventsSafely()
            async let lifeEventsTask = Self.fetchLifeEventsSafely()
            async let manualExercisesTask = Self.fetchManualExercisesSafely()

            let (
                allSleepSamples, allRMSSDSamples, allSDNNSamples, allRestingHeartRateSamples,
                allWorkouts, allMoods, allCoffees, calendarEvents, lifeEvents, manualExercises
            ) = try await (
                sleepSamplesTask, rmssdSamplesTask, sdnnSamplesTask, restingHeartRateSamplesTask,
                workoutsTask, moodsTask, coffeesTask, calendarEventsTask, lifeEventsTask, manualExercisesTask
            )
            // rMSSD/SDNN을 이미 위에서 받아왔으니, fetchSDNNRMSSDPairs()를 또 불러서 HealthKit을
            // 중복 조회하는 대신 이미 가진 배열로 짝만 짓는다.
            let allPairs = HealthKitService.pairSDNNAndRMSSD(sdnn: allSDNNSamples, rmssd: allRMSSDSamples)

            // 수면은 기간 경계에 걸친 밤이 중간에 잘리지 않도록 전체 샘플을 먼저 병합한 뒤,
            // 그 기간에 "시작하는" 밤만 추린다.
            let allRanges = SleepAnalysisService.buildSleepRanges(allSleepSamples)
            sleepRanges = allRanges
                .filter { $0.start >= start && $0.start < end }
                .sorted { $0.start < $1.start }

            if sleepRanges.isEmpty {
                averageSleepDuration = nil
                averageSleepScore = nil
            } else {
                let totalDuration = sleepRanges.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
                averageSleepDuration = totalDuration / Double(sleepRanges.count)
                averageSleepScore = Double(sleepRanges.map(\.estimatedScore).reduce(0, +)) / Double(sleepRanges.count)
            }

            let periodRMSSD = allRMSSDSamples.filter { $0.date >= start && $0.date < end }
            cvFindings = Self.computeCVFindings(periodRMSSD: periodRMSSD, allRMSSDSamples: allRMSSDSamples)
            rmssdFindings = Self.computeRMSSDFindings(
                periodRMSSD,
                allSleepRanges: allRanges,
                calendarEvents: calendarEvents
            )

            let periodSDNN = allSDNNSamples.filter { $0.date >= start && $0.date < end }.map(\.value)
            let periodRestingHeartRate = allRestingHeartRateSamples.filter { $0.date >= start && $0.date < end }.map(\.value)
            vitalMedians = VitalMedians(
                restingHeartRate: periodRestingHeartRate.isEmpty ? nil : HRVStatistics.median(periodRestingHeartRate),
                sdnn: periodSDNN.isEmpty ? nil : HRVStatistics.median(periodSDNN),
                rmssd: periodRMSSD.isEmpty ? nil : HRVStatistics.median(periodRMSSD.map(\.value))
            )

            let periodPairs = allPairs.filter { $0.date >= start && $0.date < end }
            topSDNNRMSSDDifferences = periodPairs
                .map { SDNNRMSSDDifference(date: $0.date, sdnn: $0.sdnn, rmssd: $0.rmssd) }
                .sorted { $0.difference > $1.difference }
                .prefix(3)
                .map { $0 }

            let periodWorkouts = allWorkouts
                .filter { $0.start < end && $0.end >= start }
                .map { (start: $0.start, end: $0.end) }
            let periodMoods = Self.parseMoodEntries(allMoods).filter { $0.date >= start && $0.date < end }
            let periodCoffees = Self.parseCoffeeEntries(allCoffees).filter { $0.date >= start && $0.date < end }

            correlationFindings = Self.computeCorrelations(
                dailyRMSSD: HRVStatistics.dailyMedian(periodRMSSD),
                workouts: periodWorkouts,
                moods: periodMoods,
                coffees: periodCoffees
            )

            let workoutSummaries = Self.mergedWorkoutSummaries(healthKitWorkouts: allWorkouts, manualExercises: manualExercises)
            rmssdLowestDayRows = Self.computeLowestDayRows(
                dailyMedians: HRVStatistics.dailyMedian(periodRMSSD),
                sleepRanges: allRanges,
                calendarEvents: calendarEvents,
                lifeEvents: lifeEvents,
                workoutSummaries: workoutSummaries
            )

            hasAnalyzed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 전체 CV는 기간 안의 원시 샘플만으로 계산하지만, 일별 평균의 롤링 표준편차 밴드는 기간 시작일
    // 근처도 온전한 7일 창을 갖도록 기간 제한이 없는 allRMSSDSamples에서 과거 데이터를 끌어와 쓴다.
    private static func computeCVFindings(
        periodRMSSD: [(date: Date, value: Double)],
        allRMSSDSamples: [(date: Date, value: Double)]
    ) -> CVFindings? {
        guard !periodRMSSD.isEmpty else { return nil }
        let calendar = Calendar.current

        guard let overallCV = HRVStatistics.coefficientOfVariation(periodRMSSD.map(\.value)) else { return nil }

        var samplesByDay: [Date: [Double]] = [:]
        for sample in allRMSSDSamples {
            samplesByDay[calendar.startOfDay(for: sample.date), default: []].append(sample.value)
        }

        let periodDays = Set(periodRMSSD.map { calendar.startOfDay(for: $0.date) }).sorted()

        let dailyPoints: [CVDailyPoint] = periodDays.compactMap { day -> CVDailyPoint? in
            guard let dayValues = samplesByDay[day], !dayValues.isEmpty,
                  let windowStart = calendar.date(byAdding: .day, value: -6, to: day) else { return nil }

            var windowValues: [Double] = []
            var cursor = windowStart
            while cursor <= day {
                if let values = samplesByDay[cursor] {
                    windowValues.append(contentsOf: values)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }

            let dayMean = HRVStatistics.mean(dayValues)
            let windowSD = HRVStatistics.standardDeviation(windowValues)

            return CVDailyPoint(date: day, mean: dayMean, lowerBand: dayMean - windowSD, upperBand: dayMean + windowSD)
        }

        return CVFindings(overallCV: overallCV, dailyPoints: dailyPoints)
    }

    private static func computeRMSSDFindings(
        _ samples: [(date: Date, value: Double)],
        allSleepRanges: [SleepRange],
        calendarEvents: [CalendarEventService.Event]
    ) -> RMSSDLowestFindings? {
        guard !samples.isEmpty else { return nil }
        let calendar = Calendar.current

        let dailyMedians = HRVStatistics.dailyMedian(samples)
        let lowestDay = dailyMedians.min { $0.value < $1.value }

        var byWeekday: [Int: [Double]] = [:]
        for entry in dailyMedians {
            byWeekday[calendar.component(.weekday, from: entry.date), default: []].append(entry.value)
        }
        let weekdayAverages = byWeekday.mapValues { $0.reduce(0, +) / Double($0.count) }
        let lowestWeekday = weekdayAverages.min { $0.value < $1.value }?.key

        let lowestDayContext = lowestDay.map {
            Self.lowestDayContext(date: $0.date, sleepRanges: allSleepRanges, calendarEvents: calendarEvents)
        }

        return RMSSDLowestFindings(
            lowestDailyDate: lowestDay?.date,
            lowestAverageWeekday: lowestWeekday,
            mostFrequentLowestHour: Self.mostFrequentLowestHour(samples),
            lowestDayContext: lowestDayContext
        )
    }

    // 날짜별로 그 날의 최저 1시간 버킷(0~23시, 그 시간대 원시 샘플 평균 기준)을 구한 뒤,
    // 여러 날에 걸쳐 가장 자주 "그날의 최저"로 뽑힌 시간대를 찾는다. 동률이면 더 이른
    // 시간대를 택해 항상 같은 결과가 나오게 한다.
    private static func mostFrequentLowestHour(_ samples: [(date: Date, value: Double)]) -> Int? {
        let calendar = Calendar.current

        var byDay: [Date: [Int: [Double]]] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let hour = calendar.component(.hour, from: sample.date)
            byDay[day, default: [:]][hour, default: []].append(sample.value)
        }

        let lowestHourPerDay = byDay.values.compactMap { hourBuckets in
            hourBuckets.mapValues(HRVStatistics.mean).min { $0.value < $1.value }?.key
        }
        guard !lowestHourPerDay.isEmpty else { return nil }

        var counts: [Int: Int] = [:]
        for hour in lowestHourPerDay {
            counts[hour, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maxCount }.keys.min()
    }

    // 그 날 rMSSD가 가장 낮았던 이유를 짐작해볼 수 있게, 전날/당일 수면 시간과 그날 캘린더
    // 일정을 구조화해서 넘긴다. 전날 수면 = date-1에 시작한 밤, 당일 수면 = date에 시작한 밤 —
    // 실제 날짜는 이 date를 기준으로 화면에서 계산해서 표시한다.
    private static func lowestDayContext(
        date: Date,
        sleepRanges: [SleepRange],
        calendarEvents: [CalendarEventService.Event]
    ) -> LowestDayContext {
        let calendar = Calendar.current

        let previousNightDuration = calendar.date(byAdding: .day, value: -1, to: date)
            .flatMap { previousDay in sleepRanges.first { calendar.isDate($0.start, inSameDayAs: previousDay) } }
            .map { $0.end.timeIntervalSince($0.start) }

        let sameNightDuration = sleepRanges
            .first { calendar.isDate($0.start, inSameDayAs: date) }
            .map { $0.end.timeIntervalSince($0.start) }

        let eventTitles = calendarEvents
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .map(\.title)

        return LowestDayContext(
            previousNightDuration: previousNightDuration,
            sameNightDuration: sameNightDuration,
            eventTitles: eventTitles
        )
    }

    // 캘린더 접근 권한이 없거나 거부돼도 나머지 보고서는 정상적으로 보여준다 —
    // "일정" 컨텍스트만 빠진다.
    private static func fetchCalendarEventsSafely() async -> [CalendarEventService.Event] {
        do {
            try await CalendarEventService.requestAuthorization()
            return await CalendarEventService.fetchEvents()
        } catch {
            return []
        }
    }

    // 직접 입력한 생활 이벤트(약 변경/대인관계 문제 등)도 "스케줄"에 같이 보여준다 — 실패해도
    // 나머지 보고서에는 영향 없게 한다.
    private static func fetchLifeEventsSafely() async -> [LifeEventEntry] {
        (try? await LifeEventService.allEvents()) ?? []
    }

    // 전날 운동은 HealthKit 자동 기록뿐 아니라 캘린더에서 수동으로 남긴 운동 기록도 포함한다.
    private static func fetchManualExercisesSafely() async -> [ExerciseLogEntry] {
        (try? await ExerciseService.allExercises()) ?? []
    }

    private struct WorkoutSummary {
        let start: Date
        let end: Date
        let label: String
    }

    private static func mergedWorkoutSummaries(
        healthKitWorkouts: [(start: Date, end: Date, activityType: HKWorkoutActivityType, energyBurnedKcal: Double?, distanceMeters: Double?)],
        manualExercises: [ExerciseLogEntry]
    ) -> [WorkoutSummary] {
        let fromHealthKit = healthKitWorkouts.map {
            WorkoutSummary(start: $0.start, end: $0.end, label: HealthKitService.workoutActivityTypeDisplayName($0.activityType))
        }
        let fromManual = manualExercises.compactMap { entry -> WorkoutSummary? in
            guard let start = DateKey.parseISODate(entry.startedAt), let end = DateKey.parseISODate(entry.endedAt) else { return nil }
            return WorkoutSummary(start: start, end: end, label: entry.type)
        }
        return (fromHealthKit + fromManual).sorted { $0.start < $1.start }
    }

    // rMSSD가 가장 낮았던 상위 N일을 표로 보여준다 — 일자별로 전날 수면/그날 스케줄/전날 운동을
    // 나란히 붙여, 그 날 유독 낮았던 이유를 짐작할 단서를 준다.
    private static let lowestDayRowCount = 5

    private static func computeLowestDayRows(
        dailyMedians: [(date: Date, value: Double)],
        sleepRanges: [SleepRange],
        calendarEvents: [CalendarEventService.Event],
        lifeEvents: [LifeEventEntry],
        workoutSummaries: [WorkoutSummary]
    ) -> [RMSSDLowestDayRow] {
        let calendar = Calendar.current
        let lowestDays = dailyMedians.sorted { $0.value < $1.value }.prefix(lowestDayRowCount)

        return lowestDays.map { entry in
            let previousDay = calendar.date(byAdding: .day, value: -1, to: entry.date)

            let previousNightSleepDuration = previousDay
                .flatMap { prev in sleepRanges.first { calendar.isDate($0.start, inSameDayAs: prev) } }
                .map { $0.end.timeIntervalSince($0.start) }

            let calendarTitles = calendarEvents
                .filter { calendar.isDate($0.start, inSameDayAs: entry.date) }
                .map(\.title)
            let lifeEventTitles = lifeEvents.compactMap { life -> String? in
                guard let eventDate = DateKey.parseISODate(life.date), calendar.isDate(eventDate, inSameDayAs: entry.date) else {
                    return nil
                }
                return life.title
            }

            let previousDayExercise = previousDay.flatMap { prev in
                workoutSummaries.first { calendar.isDate($0.start, inSameDayAs: prev) }
            }
            let previousDayExerciseSummary = previousDayExercise.map { workout in
                let minutes = Int(workout.end.timeIntervalSince(workout.start) / 60)
                return "\(workout.label) \(minutes)분"
            }

            return RMSSDLowestDayRow(
                date: entry.date,
                rmssd: entry.value,
                previousNightSleepDuration: previousNightSleepDuration,
                scheduleTitles: calendarTitles + lifeEventTitles,
                previousDayExerciseSummary: previousDayExerciseSummary
            )
        }
    }

    private static func computeCorrelations(
        dailyRMSSD: [(date: Date, value: Double)],
        workouts: [(start: Date, end: Date)],
        moods: [(date: Date, score: Int)],
        coffees: [(date: Date, count: Int)]
    ) -> CorrelationFindings {
        let calendar = Calendar.current
        let rmssdByDay = Dictionary(uniqueKeysWithValues: dailyRMSSD.map { (calendar.startOfDay(for: $0.date), $0.value) })

        let moodPairs: [(Double, Double)] = moods.compactMap { mood in
            guard let rmssd = rmssdByDay[calendar.startOfDay(for: mood.date)] else { return nil }
            return (Double(mood.score), rmssd)
        }

        let coffeePairs: [(Double, Double)] = coffees.compactMap { coffee in
            guard let rmssd = rmssdByDay[calendar.startOfDay(for: coffee.date)] else { return nil }
            return (Double(coffee.count), rmssd)
        }

        let exerciseDays = Set(workouts.map { calendar.startOfDay(for: $0.start) })
        var exerciseValues: [Double] = []
        var restValues: [Double] = []
        var exercisePairs: [(Double, Double)] = []
        for (day, value) in rmssdByDay {
            if exerciseDays.contains(day) {
                exerciseValues.append(value)
                exercisePairs.append((1, value))
            } else {
                restValues.append(value)
                exercisePairs.append((0, value))
            }
        }

        return CorrelationFindings(
            moodRMSSDCorrelation: HRVStatistics.pearsonCorrelation(moodPairs),
            coffeeRMSSDCorrelation: HRVStatistics.pearsonCorrelation(coffeePairs),
            exerciseDayAverageRMSSD: exerciseValues.isEmpty ? nil : exerciseValues.reduce(0, +) / Double(exerciseValues.count),
            restDayAverageRMSSD: restValues.isEmpty ? nil : restValues.reduce(0, +) / Double(restValues.count),
            exerciseRMSSDCorrelation: HRVStatistics.pearsonCorrelation(exercisePairs)
        )
    }

    // MoodLogEntry.date는 "yyyy-MM-dd"(DateKey.string(from:)로 생성), CoffeeLogEntry.date는
    // ISO 8601(logCoffee가 ISO8601DateFormatter로 생성)이라 파싱 방식이 서로 다르다.
    private static let moodDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    private static func parseMoodEntries(_ entries: [MoodLogEntry]) -> [(date: Date, score: Int)] {
        entries.compactMap { entry in
            guard let date = moodDateFormatter.date(from: entry.date) else { return nil }
            return (date: date, score: entry.score)
        }
    }

    private static func parseCoffeeEntries(_ entries: [CoffeeLogEntry]) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for entry in entries {
            guard let date = DateKey.parseISODate(entry.date) else { continue }
            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
        return counts.map { (date: $0.key, count: $0.value) }
    }
}
