import Foundation

// 정신과 진료용 요약 보고서 — 이전 진료일부터 이번 진료일까지 기간을 골라 "분석"을 누르면
// 그 기간의 수면/rMSSD/SDNN 비교/기분·운동·커피 상관관계를 한 번에 계산해서 보여준다.
@MainActor
@Observable
final class ReportViewModel {
    struct RMSSDLowestFindings {
        // 일별 대표값(중앙값) 중 가장 낮은 날.
        let lowestDailyDate: Date?
        // 원시(시간별) 샘플 중 가장 낮은 값의 정확한 시각.
        let lowestRawSample: (date: Date, value: Double)?
        // 일별 대표값을 요일별로 평균 냈을 때 가장 낮은 요일 (1=일요일 ... 7=토요일).
        let lowestAverageWeekday: Int?
    }

    struct SDNNRMSSDDifference: Identifiable {
        let id = UUID()
        let date: Date
        let sdnn: Double
        let rmssd: Double
        var difference: Double { abs(sdnn - rmssd) }
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
    }

    var previousVisitDate: Date
    var thisVisitDate: Date

    private(set) var isAnalyzing = false
    private(set) var errorMessage: String?
    private(set) var hasAnalyzed = false

    private(set) var sleepRanges: [SleepRange] = []
    private(set) var averageSleepDuration: TimeInterval?
    private(set) var averageSleepScore: Double?
    private(set) var rmssdFindings: RMSSDLowestFindings?
    private(set) var topSDNNRMSSDDifferences: [SDNNRMSSDDifference] = []
    private(set) var correlationFindings: CorrelationFindings?

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
            async let pairsTask = HealthKitService.fetchSDNNRMSSDPairs()
            async let workoutsTask = HealthKitService.fetchWorkoutRanges()
            async let moodsTask = MoodService.allMoods()
            async let coffeesTask = CoffeeService.allCoffees()

            let (allSleepSamples, allRMSSDSamples, allPairs, allWorkouts, allMoods, allCoffees) = try await (
                sleepSamplesTask, rmssdSamplesTask, pairsTask, workoutsTask, moodsTask, coffeesTask
            )

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
            rmssdFindings = Self.computeRMSSDFindings(periodRMSSD)

            let periodPairs = allPairs.filter { $0.date >= start && $0.date < end }
            topSDNNRMSSDDifferences = periodPairs
                .map { SDNNRMSSDDifference(date: $0.date, sdnn: $0.sdnn, rmssd: $0.rmssd) }
                .sorted { $0.difference > $1.difference }
                .prefix(3)
                .map { $0 }

            let periodWorkouts = allWorkouts.filter { $0.start < end && $0.end >= start }
            let periodMoods = Self.parseMoodEntries(allMoods).filter { $0.date >= start && $0.date < end }
            let periodCoffees = Self.parseCoffeeEntries(allCoffees).filter { $0.date >= start && $0.date < end }

            correlationFindings = Self.computeCorrelations(
                dailyRMSSD: HRVStatistics.dailyMedian(periodRMSSD),
                workouts: periodWorkouts,
                moods: periodMoods,
                coffees: periodCoffees
            )

            hasAnalyzed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func computeRMSSDFindings(_ samples: [(date: Date, value: Double)]) -> RMSSDLowestFindings? {
        guard !samples.isEmpty else { return nil }
        let calendar = Calendar.current

        let dailyMedians = HRVStatistics.dailyMedian(samples)
        let lowestDay = dailyMedians.min { $0.value < $1.value }
        let lowestRaw = samples.min { $0.value < $1.value }

        var byWeekday: [Int: [Double]] = [:]
        for entry in dailyMedians {
            byWeekday[calendar.component(.weekday, from: entry.date), default: []].append(entry.value)
        }
        let weekdayAverages = byWeekday.mapValues { $0.reduce(0, +) / Double($0.count) }
        let lowestWeekday = weekdayAverages.min { $0.value < $1.value }?.key

        return RMSSDLowestFindings(
            lowestDailyDate: lowestDay?.date,
            lowestRawSample: lowestRaw,
            lowestAverageWeekday: lowestWeekday
        )
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
        for (day, value) in rmssdByDay {
            if exerciseDays.contains(day) {
                exerciseValues.append(value)
            } else {
                restValues.append(value)
            }
        }

        return CorrelationFindings(
            moodRMSSDCorrelation: HRVStatistics.pearsonCorrelation(moodPairs),
            coffeeRMSSDCorrelation: HRVStatistics.pearsonCorrelation(coffeePairs),
            exerciseDayAverageRMSSD: exerciseValues.isEmpty ? nil : exerciseValues.reduce(0, +) / Double(exerciseValues.count),
            restDayAverageRMSSD: restValues.isEmpty ? nil : restValues.reduce(0, +) / Double(restValues.count)
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
