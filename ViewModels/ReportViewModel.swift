import Foundation
import HealthKit

// 정신과 진료용 요약 보고서 — 이전 진료일부터 이번 진료일까지 기간을 골라 "분석"을 누르면
// 그 기간의 수면/rMSSD/SDNN 비교/기분·운동·커피 상관관계를 한 번에 계산해서 보여준다.
@MainActor
@Observable
final class ReportViewModel {
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

    // "가장 낮은 요일"/"낮은 시간대" 두 패널에 쓰는 값 — 날짜별 상세 컨텍스트(가장 낮은 날짜,
    // 그날 수면/캘린더 일정)까지는 필요 없어서 그 두 값만 남긴 가벼운 버전이다.
    struct RMSSDLowestFindings {
        // 일별 대표값을 요일별로 평균 냈을 때 가장 낮은 요일 (1=일요일 ... 7=토요일).
        let lowestAverageWeekday: Int?
        // 날짜별로 그 날의 최저 1시간 버킷(0~23시)을 구한 뒤, 여러 날에 걸쳐 가장 자주
        // "그날의 최저"로 뽑힌 시간대(최빈값).
        let mostFrequentLowestHour: Int?
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

    // "하루 패턴" — 선택 기간 전체의 원시 rMSSD를 한 시간 단위로 묶은 분포 통계.
    struct HourOfDayPoint: Identifiable {
        let hour: Int
        let mean: Double
        let standardDeviation: Double
        var lowerBand: Double { mean - standardDeviation }
        var upperBand: Double { mean + standardDeviation }
        var id: Int { hour }
    }

    struct CorrelationFindings {
        // 기분 점수 vs 그날 rMSSD 중앙값의 Pearson 상관계수.
        let moodRMSSDCorrelation: Double?
        // 그날 커피 잔 수 vs rMSSD 중앙값의 Pearson 상관계수.
        let coffeeRMSSDCorrelation: Double?
        // 전날 운동 여부(0/1)와 그날 rMSSD의 점-이연 상관계수 — 회복 효과를 보려는 거라 그날이
        // 아니라 전날 운동 여부를 그날 rMSSD와 짝짓는다.
        let exerciseRMSSDCorrelation: Double?
        // 전날 밤 수면 시간(시간 단위) vs 그날 rMSSD 중앙값의 Pearson 상관계수.
        let sleepDurationRMSSDCorrelation: Double?
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
    private(set) var hourOfDayPattern: [HourOfDayPoint] = []
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
        // 재분석 중에도 hasAnalyzed를 false로 내리지 않는다 — 그러면 ReportView가 이전 결과
        // 섹션을 통째로 걷어내고 전체 화면 로더로 바꿔버려서, 그 섹션 안에 있는
        // chartLoadingOverlay(이전 차트 위에 로딩 표시만 겹치기)가 아예 나타날 기회가 없다.
        defer { isAnalyzing = false }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: previousVisitDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: thisVisitDate)) else {
            hasAnalyzed = false
            errorMessage = "날짜 범위를 계산할 수 없어요."
            return
        }

        do {
            try await HealthKitService.requestAuthorization()

            // 아래 각 타입마다 실제로 필요한 만큼만 며칠 앞당겨서 가져온다 — 전부 인자 없이
            // 부르면 HealthKit에 기록된 전체 역사를 매번 다 가져와서 느려진다(예전엔 실제로
            // 그랬다). 필요한 lookback은 타입마다 다르다:
            // - 수면: 추정 수면 점수의 취침시간 일관성 계산이 이전 최대 6일 밤과 비교하므로
            //   (SleepAnalysisService.bedtimeConsistencyWindow) 그만큼 앞당기고, 기간 시작일 전날
            //   저녁에 잠들어 시작일 새벽까지 이어지는 밤이 안 잘리게 하루를 더 둔다 — 이만큼
            //   안 당기면 기간 첫날들이 "비교할 밤이 부족해서" 일관성 만점 처리돼 점수가 왜곡된다.
            // - rMSSD: CV 롤링 표준편차가 기간 시작일 근처도 온전한 7일 창을 보게 7일 전.
            // - 운동: "전날 운동" 상관계수·rMSSD 최저점의 전날 운동 요약이 기간 시작일의 전날도
            //   봐야 하니 1일 전.
            // - SDNN/안정시 심박수: 전부 기간 안의 값만 쓰므로 lookback이 필요 없다.
            // 종료일 밤(그날 저녁에 잠들어 다음날 새벽에 깨는 마지막 밤)도 안 잘리게, 수면만 종료
            // 경계도 하루 뒤로 넉넉히 늘린다 — 여기서 안 늘리면 마지막 밤이 자정에서 뚝 끊겨서
            // 그 밤의 길이·단계 구성·점수·평균·수면시간 상관계수가 전부 실제보다 짧게 나온다.
            let sleepFetchStart = calendar.date(byAdding: .day, value: -(SleepAnalysisService.bedtimeConsistencyWindow + 1), to: start) ?? start
            let sleepFetchEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            let rmssdFetchStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
            let workoutFetchStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
            async let sleepSamplesTask = HealthKitService.fetchSleepStageSamples(start: sleepFetchStart, end: sleepFetchEnd)
            async let rmssdSamplesTask = HealthKitService.fetchRMSSDSamples(start: rmssdFetchStart, end: end)
            async let sdnnSamplesTask = HealthKitService.fetchSDNNSamples(start: start, end: end)
            async let restingHeartRateSamplesTask = HealthKitService.fetchRestingHeartRateSamples(start: start, end: end)
            async let workoutsTask = HealthKitService.fetchWorkoutRanges(start: workoutFetchStart, end: end)
            async let moodsTask = MoodService.allMoods()
            async let coffeesTask = CoffeeService.allCoffees()
            async let calendarEventsTask = Self.fetchCalendarEventsSafely(start: start, end: end)
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
            // 그 기간에 속하는 밤만 추린다 — 세션의 실제 시작 시각이 아니라 나이트 라벨(위 "수면"
            // 참고: 오전 10시 이전 시작은 전날 밤으로 취급)로 판정해야, 이 목록이 차트에 실제로
            // 그려지는 밤과 정확히 일치한다. 그렇지 않으면 기간 첫날 새벽에 시작한 세션이 차트에는
            // (나이트 라벨상 전날로 밀려) 안 보이는데 평균·집계에는 그대로 들어가는 식으로 화면과
            // 숫자가 어긋난다.
            let allRanges = SleepAnalysisService.buildSleepRanges(allSleepSamples)
            sleepRanges = allRanges
                .filter { let label = SleepAnalysisService.nightLabel(for: $0.start); return label >= start && label < end }
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
            rmssdFindings = Self.computeRMSSDFindings(periodRMSSD)
            hourOfDayPattern = Self.computeHourOfDayPattern(periodRMSSD)

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

            let periodMoods = Self.parseMoodEntries(allMoods).filter { $0.date >= start && $0.date < end }
            let periodCoffees = Self.parseCoffeeEntries(allCoffees).filter { $0.date >= start && $0.date < end }

            // HealthKit 운동과 수동 입력 운동(캘린더 ExerciseEntryForm)을 합친다 — HealthKit 연동이
            // 안 된 수동 기록만 있는 날을 "전날 운동" 상관계수와 아래 rMSSD 최저일 요약 둘 다에서
            // 똑같이 운동한 날로 잡아야 한다.
            let workoutSummaries = Self.mergedWorkoutSummaries(healthKitWorkouts: allWorkouts, manualExercises: manualExercises)

            // "전날 운동" 상관계수는 기간 첫날의 전날(기간 시작일 하루 전, workoutFetchStart부터
            // 이미 가져와 둔 범위)도 봐야 하므로, 기간(start...end)으로 좁힌 목록이 아니라 이미
            // 알맞게 앞당겨 가져온 workoutSummaries를 그대로 쓴다 — 좁히면 기간 첫날 전날의 운동이
            // 통째로 빠져서 그날이 실제로는 운동한 날인데도 "쉬는 날"로 잘못 분류된다.
            correlationFindings = Self.computeCorrelations(
                dailyRMSSD: HRVStatistics.dailyMedian(periodRMSSD),
                workouts: workoutSummaries.map { (start: $0.start, end: $0.end) },
                moods: periodMoods,
                coffees: periodCoffees,
                sleepRanges: allRanges
            )

            rmssdLowestDayRows = Self.computeLowestDayRows(
                dailyMedians: HRVStatistics.dailyMedian(periodRMSSD),
                sleepRanges: allRanges,
                calendarEvents: calendarEvents,
                lifeEvents: lifeEvents,
                workoutSummaries: workoutSummaries
            )

            hasAnalyzed = true
        } catch {
            // 재분석이 실패하면 이전 결과를 그대로 남겨두지 않는다 — 위 기간 텍스트는 이미 새로
            // 고른 기간으로 바뀌어 있는데, 화면엔 실패한 새 기간이 아니라 이전(다른) 기간의 결과가
            // 그대로 남아 마치 그게 새 기간 결과인 것처럼 보이면 안 된다. 로딩 중에만 이전 결과를
            // 살려 두고(위 chartLoadingOverlay), 실패가 확정되면 지운다.
            hasAnalyzed = false
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

    private static func computeRMSSDFindings(_ samples: [(date: Date, value: Double)]) -> RMSSDLowestFindings? {
        guard !samples.isEmpty else { return nil }
        let calendar = Calendar.current

        let dailyMedians = HRVStatistics.dailyMedian(samples)

        var byWeekday: [Int: [Double]] = [:]
        for entry in dailyMedians {
            byWeekday[calendar.component(.weekday, from: entry.date), default: []].append(entry.value)
        }
        let weekdayAverages = byWeekday.mapValues { $0.reduce(0, +) / Double($0.count) }
        let lowestWeekday = weekdayAverages.min { $0.value < $1.value }?.key

        return RMSSDLowestFindings(
            lowestAverageWeekday: lowestWeekday,
            mostFrequentLowestHour: Self.mostFrequentLowestHour(samples)
        )
    }

    // 선택 기간 전체의 원시 rMSSD 샘플을 시(0~23)별로 모아 평균·표준편차를 계산한다.
    // 샘플이 하나도 없는 시간대는 배열에서 아예 빼서 "실제로 0이었다"는 오해를 막는다.
    private static func computeHourOfDayPattern(_ samples: [(date: Date, value: Double)]) -> [HourOfDayPoint] {
        let calendar = Calendar.current
        var byHour: [Int: [Double]] = [:]
        for sample in samples {
            byHour[calendar.component(.hour, from: sample.date), default: []].append(sample.value)
        }
        return byHour.compactMap { hour, values in
            guard !values.isEmpty else { return nil }
            return HourOfDayPoint(
                hour: hour,
                mean: HRVStatistics.mean(values),
                standardDeviation: HRVStatistics.standardDeviation(values)
            )
        }
        .sorted { $0.hour < $1.hour }
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

    // 캘린더 접근 권한이 없거나 거부돼도 나머지 보고서는 정상적으로 보여준다 —
    // "일정" 컨텍스트만 빠진다.
    private static func fetchCalendarEventsSafely(start: Date, end: Date) async -> [CalendarEventService.Event] {
        do {
            try await CalendarEventService.requestAuthorization()
            return await CalendarEventService.fetchEvents(start: start, end: end)
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
    private static let lowestDayRowCount = 3

    // 이 단어가 제목에 들어간 캘린더 일정은 매일 반복되는 정례 일정이라 스케줄 목록에서 뺀다.
    private static let excludedScheduleKeywords = ["scrum", "booktudy"]

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

            // 나이트 라벨(위 "수면" 참고)로 그날 밤을 판정해야 한다 — 세션의 실제 시작 시각으로
            // 비교하면 자정 넘어 시작한 세션이 하루 밀려서 빠지거나 엉뚱한 밤으로 잡힌다. 같은 밤에
            // 세션이 여러 개(이른 아침에 잠깐 더 잔 것 + 그날 밤잠)면 합산한다.
            let previousNightSleepDuration: TimeInterval? = previousDay.flatMap { prev -> TimeInterval? in
                let matching = sleepRanges.filter {
                    calendar.isDate(SleepAnalysisService.nightLabel(for: $0.start), inSameDayAs: prev)
                }
                guard !matching.isEmpty else { return nil }
                return matching.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
            }

            // 시작일만 비교하면 여러 날에 걸친 일정(휴가·출장 등)이 둘째 날부터는 누락된다 —
            // 일정 구간과 그날 하루 구간이 겹치는지로 판정해야 한다.
            let dayStart = calendar.startOfDay(for: entry.date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            // 매일 반복되는 정례 회의(Scrum/BookStudy 등)는 그날의 특별한 스케줄이라 보기
            // 어려워서 뺀다.
            let calendarTitles = calendarEvents
                .filter { $0.start < dayEnd && $0.end > dayStart }
                .map(\.title)
                .filter { title in
                    !Self.excludedScheduleKeywords.contains { title.localizedCaseInsensitiveContains($0) }
                }
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
        coffees: [(date: Date, count: Int)],
        sleepRanges: [SleepRange]
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

        // 그날 운동이 아니라 "전날" 운동 여부와 그날 rMSSD를 짝짓는다 — 운동의 회복 효과가
        // 다음날 HRV에 나타나는지를 보려는 것.
        let exerciseDays = Set(workouts.map { calendar.startOfDay(for: $0.start) })
        var exercisePairs: [(Double, Double)] = []
        for (day, value) in rmssdByDay {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { continue }
            exercisePairs.append((exerciseDays.contains(previousDay) ? 1 : 0, value))
        }

        // 전날 밤 수면 시간(시간 단위)과 그날 rMSSD를 짝짓는다. 하루에 세션이 2개 이상(예: 이른
        // 아침에 잠깐 더 잔 것 + 그날 밤잠)이면 같은 날짜 키가 중복되므로 uniqueKeysWithValues는
        // 크래시한다 — 합산(+)으로 합쳐서 그날 총 수면시간을 쓴다.
        // 자정 넘어 시작한 세션(예: 7/2 00:30 시작)은 raw startOfDay로 키를 잡으면 그날(7/2) 것으로
        // 잡히는데, 실제로는 전날(7/1) 밤이 이어진 것이라 위 exercisePairs와 같은 기준(nightLabel)으로
        // 키를 잡아야 한다 — 안 그러면 7/2 rMSSD와 짝지어야 할 전날(7/1) 밤 수면이 여기서 빠지고,
        // 대신 7/3 rMSSD와 잘못 짝지어진다.
        let sleepDurationByDay = Dictionary(
            sleepRanges.map { (SleepAnalysisService.nightLabel(for: $0.start), $0.end.timeIntervalSince($0.start) / 3600) },
            uniquingKeysWith: +
        )
        let sleepPairs: [(Double, Double)] = rmssdByDay.compactMap { day, value in
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
                  let duration = sleepDurationByDay[previousDay] else { return nil }
            return (duration, value)
        }

        return CorrelationFindings(
            moodRMSSDCorrelation: HRVStatistics.pearsonCorrelation(moodPairs),
            coffeeRMSSDCorrelation: HRVStatistics.pearsonCorrelation(coffeePairs),
            exerciseRMSSDCorrelation: HRVStatistics.pearsonCorrelation(exercisePairs),
            sleepDurationRMSSDCorrelation: HRVStatistics.pearsonCorrelation(sleepPairs)
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
