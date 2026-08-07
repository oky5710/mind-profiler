import Foundation

// 오늘의 수사 노트 튜닝값. 표시 개수와 조회 기간을 바꾸려면 이곳만 수정한다.
enum DailyBriefingConfiguration {
    static let maximumDisplayedClues = 10
    static let evidenceLookbackDays = 1
    static let sleepBaselineNightCount = 30
    static let sleepFetchBufferDays = 8

    static let sleepDurationThresholdMinutes = 30.0
    static let awakeDurationThresholdMinutes = 5.0
    static let continuousSleepThresholdMinutes = 30.0
    static let rmssdChangeThresholdPercent = 15.0
    static let lateCoffeeStartHour = 15
    static let veryLateCoffeeStartHour = 18
    static let minimumWorkoutMinutes = 30.0
    // 현재 운동 강도는 1...5이므로 4(힘듦)부터 고강도로 본다.
    static let highIntensityWorkoutMinimum = 4.0
    static let longScheduleMinimumMinutes = 60.0
    static let busyScheduleMinimumHours = 6.0
    static let manySchedulesMinimumCount = 3
    static let noteMaximumLength = 18
    static let maximumTodayClues = 2
}

enum RecoveryScoreConfiguration {
    // 통합 편차(combinedZ) == 0(최근 30일 기준과 동일한 상태)일 때 몇 점으로 보일지. 50점은
    // "평균"이라는 통계적 의미보다 "절반밖에 회복되지 않았다"로 읽혀서, 평소 상태를 75점으로
    // 올리고 편차 1당 배점(10)도 같이 낮춰 0~100 끝까지 쓰기 쉽게 했다.
    static let baseScore = 75.0
    static let pointsPerZScore = 10.0
    static let minimumScore = 0.0
    static let maximumScore = 100.0
}

struct RecoveryScore {
    let value: Int

    var label: String {
        switch value {
        case 90...: "Excellent"
        case 80..<90: "Good"
        case 70..<80: "Typical"
        default: "Low"
        }
    }
}

enum RecoveryScoreBuilder {
    private enum Period: CaseIterable, Hashable { case morning, afternoon, sleep }

    static func build(
        samples: [(date: Date, value: Double)],
        sleepRanges: [SleepRange],
        day: Date = Date()
    ) -> RecoveryScore? {
        guard let combinedZ = combinedZScore(samples: samples, sleepRanges: sleepRanges, day: day) else {
            return nil
        }
        return score(forZ: combinedZ)
    }

    // 최종 점수 변환(baseScore + z × pointsPerZScore)과 분리해 둔다 — 진단용 분포 확인 도구가
    // 같은 z 하나로 여러 배점 후보를 동시에 비교해볼 수 있게 하기 위함(RecoveryScoreDistributionView 참고).
    static func combinedZScore(
        samples: [(date: Date, value: Double)],
        sleepRanges: [SleepRange],
        day: Date = Date()
    ) -> Double? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: day)
        var history: [Period: [Double]] = [:]
        var current: [Period: [Double]] = [:]

        for sample in samples {
            let period = period(for: sample.date, sleepRanges: sleepRanges, calendar: calendar)
            if sample.date < today {
                history[period, default: []].append(sample.value)
            } else if calendar.isDate(sample.date, inSameDayAs: today) {
                current[period, default: []].append(sample.value)
            }
        }

        let zScores = Period.allCases.compactMap { period -> Double? in
            guard let historyValues = history[period], !historyValues.isEmpty,
                  let currentValues = current[period], !currentValues.isEmpty else { return nil }
            let median = HRVStatistics.median(historyValues)
            let mad = HRVStatistics.median(historyValues.map { abs($0 - median) })
            guard mad > 0 else { return nil }
            return (HRVStatistics.median(currentValues) - median) / mad
        }
        guard !zScores.isEmpty else { return nil }
        return zScores.reduce(0, +) / Double(zScores.count)
    }

    static func score(
        forZ combinedZ: Double,
        baseScore: Double = RecoveryScoreConfiguration.baseScore,
        pointsPerZScore: Double = RecoveryScoreConfiguration.pointsPerZScore
    ) -> RecoveryScore {
        let rawScore = baseScore + combinedZ * pointsPerZScore
        return RecoveryScore(value: Int(rawScore.clamped(
            to: RecoveryScoreConfiguration.minimumScore...RecoveryScoreConfiguration.maximumScore
        ).rounded()))
    }

    private static func period(
        for date: Date,
        sleepRanges: [SleepRange],
        calendar: Calendar
    ) -> Period {
        if sleepRanges.contains(where: { date >= $0.start && date <= $0.end }) { return .sleep }
        return calendar.component(.hour, from: date) < 12 ? .morning : .afternoon
    }
}

// 수사 기록하기 위에 보여줄 오늘 하루 요약 문구. 각 지표를 최근 30일 기준과 비교해 조건에 맞을 때만
// 고정된 문장 하나를 붙인다 — 구체적 수치는 보여주지 않는다. 단서/사건명과 달리 개수 제한이나
// 우선순위가 없고, 조건에 안 걸리면 그 지표는 조용히 건너뛴다.
enum DailySummaryConfiguration {
    static let sleepDurationThresholdPercent = 20.0
    static let sleepRecoveryThresholdPercent = 20.0
    static let awakeRatioThresholdPercent = 20.0
    static let bedtimeThresholdMinutes = 120.0
    static let restingHeartRateThresholdPercent = 15.0
    static let dailyRMSSDThresholdPercent = 20.0
    static let exerciseDurationThresholdPercent = 30.0
    static let morningRecoveryThresholdPercent = 20.0
    // 2시간 미만은 낮잠 등으로 보고 "수면 시간" 지표 집계에서 제외한다.
    static let minimumSleepDurationMinutes = 120.0
    // 하루가 아직 많이 남았을 때 "활동량이 적은 하루"라고 성급히 판단하지 않도록, 오늘 기준으로는
    // 이 시각 이후에만 이 문구를 보여준다. 지난 날짜는 하루가 이미 끝났으니 시간과 무관하게 보여준다.
    static let lowActivityMessageEarliestHour = 18
}

struct DailySummaryHighlight: Identifiable {
    let id = UUID()
    let message: String
}

struct DailySummaryInput {
    let sleepDurationChangePercent: Double?
    let sleepRecoveryRMSSDChangePercent: Double?
    let awakeRatioChangePercent: Double?
    // 절대 시간(분) 차이 — 취침 시각은 비율이 아니라 "2시간 이상 차이"로 판정한다.
    let bedtimeChangeMinutes: Double?
    let restingHeartRateChangePercent: Double?
    let dailyRMSSDChangePercent: Double?
    let exerciseDurationChangePercent: Double?
    // 오늘이면 아직 하루가 남아있어 "활동량이 적었다"고 성급히 말하지 않도록, 이 값이 false면
    // 활동량이 적다는 문구는 건너뛴다(많았다는 문구는 시간과 무관하게 보여준다).
    let canShowLowActivityMessage: Bool
    let morningRecoveryChangePercent: Double?
}

// 지표 하나를 "평소보다 얼마나 바뀌었는지 → 임계값을 넘으면 고정 문구 하나" 규칙으로 판정한다.
// change가 -threshold 이하면 lowMessage, +threshold 이상이면 highMessage, 둘 다 아니면(또는
// change 자체가 없으면) 아무 신호도 내지 않는다 — 두 조건은 항상 서로 배타적이라 어느 쪽을 먼저
// 검사하든 결과가 같다.
private struct DailyThresholdSignal {
    let change: Double?
    let threshold: Double
    let lowMessage: String
    let highMessage: String
    // 활동량이 적었다는 신호처럼, 임계값을 넘어도 별도 조건(하루가 아직 안 끝남 등)에 따라
    // lowMessage를 억눌러야 하는 지표가 있어서 기본값 true로 둔다.
    var canShowLow = true

    var message: String? {
        guard let change else { return nil }
        if change <= -threshold, canShowLow { return lowMessage }
        if change >= threshold { return highMessage }
        return nil
    }
}

enum DailySummaryBuilder {
    static func build(from input: DailySummaryInput) -> [DailySummaryHighlight] {
        // 수면 시간 부족은 회복에 가장 직접적으로 영향을 주는 지표라, 다른 신호가 같이 뜨는 날에도
        // 항상 맨 위에 오도록 따로 빼서 맨 끝에 앞으로 꽂는다. "충분한 수면"은 부족만큼 급하게 알 필요는
        // 없어서 다른 지표처럼 평범한 순서로 둔다(아래 signals의 sleepDuration 항목이 그 역할).
        let isSleepDurationShort = input.sleepDurationChangePercent.map {
            $0 <= -DailySummaryConfiguration.sleepDurationThresholdPercent
        } ?? false

        let signals: [DailyThresholdSignal] = [
            DailyThresholdSignal(
                change: input.sleepDurationChangePercent,
                threshold: DailySummaryConfiguration.sleepDurationThresholdPercent,
                lowMessage: "", // 짧은 수면 문구는 위 isSleepDurationShort로 따로 맨 앞에 꽂는다.
                highMessage: "🛌 충분한 수면을 취했어요.",
                canShowLow: false
            ),
            DailyThresholdSignal(
                change: input.sleepRecoveryRMSSDChangePercent,
                threshold: DailySummaryConfiguration.sleepRecoveryThresholdPercent,
                lowMessage: "🌿 수면 중 회복이 평소보다 느렸어요.",
                highMessage: "🌿 수면 중 회복이 평소보다 잘 이루어졌어요."
            ),
            DailyThresholdSignal(
                change: input.awakeRatioChangePercent,
                threshold: DailySummaryConfiguration.awakeRatioThresholdPercent,
                lowMessage: "🌙 밤사이 잠이 안정적으로 이어졌어요.",
                highMessage: "🌙 밤사이 잠이 평소보다 자주 끊겼어요."
            ),
            DailyThresholdSignal(
                change: input.bedtimeChangeMinutes,
                threshold: DailySummaryConfiguration.bedtimeThresholdMinutes,
                lowMessage: "🌃 평소보다 일찍 잠들었어요.",
                highMessage: "🌃 평소보다 늦게 잠들었어요."
            ),
            DailyThresholdSignal(
                change: input.restingHeartRateChangePercent,
                threshold: DailySummaryConfiguration.restingHeartRateThresholdPercent,
                lowMessage: "❤️ 몸이 편안하게 쉬고 있었어요.",
                highMessage: "❤️ 심장이 평소보다 조금 바빴어요."
            ),
            DailyThresholdSignal(
                change: input.dailyRMSSDChangePercent,
                threshold: DailySummaryConfiguration.dailyRMSSDThresholdPercent,
                lowMessage: "🌿 회복 신호가 평소보다 약했어요.",
                highMessage: "🌿 회복 신호가 평소보다 좋았어요."
            ),
            DailyThresholdSignal(
                change: input.exerciseDurationChangePercent,
                threshold: DailySummaryConfiguration.exerciseDurationThresholdPercent,
                lowMessage: "🪫 활동량이 적은 하루였어요.",
                highMessage: "💪 몸을 많이 사용한 하루였어요.",
                canShowLow: input.canShowLowActivityMessage
            ),
            DailyThresholdSignal(
                change: input.morningRecoveryChangePercent,
                threshold: DailySummaryConfiguration.morningRecoveryThresholdPercent,
                lowMessage: "☀️ 아침에 몸이 천천히 깨어났어요.",
                highMessage: "☀️ 아침부터 회복 신호가 좋았어요."
            ),
        ]

        var messages = signals.compactMap(\.message)
        if isSleepDurationShort {
            messages.insert("🛌 수면 시간이 평소보다 짧았어요.", at: 0)
        }

        return messages.map { DailySummaryHighlight(message: $0) }
    }
}

enum LongTermCaseConfiguration {
    static let analysisDays = 90
    static let minimumSampleCount = 10
}

enum UnsolvedCaseType: String, CaseIterable, Identifiable {
    case coffeeAndSleep, exerciseAndMorningRMSSD, sleepAndMorningRMSSD, commuteAndRMSSD
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .coffeeAndSleep: "☕"
        case .exerciseAndMorningRMSSD: "🏋️"
        case .sleepAndMorningRMSSD: "😴"
        case .commuteAndRMSSD: "🚇"
        }
    }

    var title: String {
        switch self {
        case .coffeeAndSleep: "늦은 커피는 수면을 줄이는가?"
        case .exerciseAndMorningRMSSD: "운동은 다음 날 회복에 영향을 주는가?"
        case .sleepAndMorningRMSSD: "충분한 수면은 아침 rMSSD를 높이는가?"
        case .commuteAndRMSSD: "출근은 rMSSD에 영향을 주는가?"
        }
    }
}

enum EvidenceStrength {
    case insufficient, none, weak, moderate, strong
    var rank: Int {
        switch self {
        case .insufficient: 0
        case .none: 1
        case .weak: 2
        case .moderate: 3
        case .strong: 4
        }
    }
    var label: String {
        switch self {
        case .insufficient: "증거 수집 중"
        case .none: "뚜렷한 단서 없음"
        case .weak: "약한 단서"
        case .moderate: "유력한 단서"
        case .strong: "강한 단서"
        }
    }
}

struct UnsolvedCaseResult: Identifiable {
    let type: UnsolvedCaseType
    let sampleCount: Int
    let correlation: Double?
    let strength: EvidenceStrength
    let summary: String
    let detail: String
    let insight: CaseInsight?
    var id: UnsolvedCaseType { type }
}

struct CaseInsight {
    let title: String
    let summary: String
    let evidence: String

    static let caution = "※ 아직은 유력한 용의자입니다. 사건을 종결하려면 조금 더 많은 증거가 필요합니다."
}

private struct CaseInsightTemplate {
    let positivePattern: String
    let negativePattern: String
    let positiveInterpretation: String
    let negativeInterpretation: String

    func make(isPositive: Bool, sampleCount: Int, unit: String, strength: EvidenceStrength) -> CaseInsight {
        let lead = strength == .strong
            ? "반복적으로 같은 패턴이 관찰되었어요."
            : "관련성이 의심되는 방향이 관찰되었지만 조금 더 확인이 필요해요."
        return CaseInsight(
            title: strength == .strong ? "🕵️ 강한 단서 발견" : "🕵️ 유력한 단서 발견",
            summary: "\(lead) \(isPositive ? positivePattern : negativePattern)",
            evidence: "최근 \(LongTermCaseConfiguration.analysisDays)일 동안 증거 \(sampleCount)\(unit)를 확보했어요. "
                + (isPositive ? positiveInterpretation : negativeInterpretation)
        )
    }
}

struct LongTermCoffeeRecord { let date: Date }
struct LongTermWorkoutRecord { let start: Date; let durationMinutes: Double }
struct LongTermNightSleepRecord { let nightDate: Date; let sleepMinutes: Double }
struct LongTermDailyRMSSD { let date: Date; let median: Double }
enum LongTermCommuteStatus { case workday, nonWorkday, unclassified }

enum LongTermCaseAnalyzer {
    static func analyze(
        coffees: [LongTermCoffeeRecord],
        workouts: [LongTermWorkoutRecord],
        sleeps: [LongTermNightSleepRecord],
        morningRMSSD: [LongTermDailyRMSSD],
        dailyRMSSD: [LongTermDailyRMSSD],
        commuteStatusByDay: [Date: LongTermCommuteStatus]
    ) -> [UnsolvedCaseResult] {
        let calendar = Calendar.current
        let sleepByNight = Dictionary(sleeps.map { (calendar.startOfDay(for: $0.nightDate), $0) }, uniquingKeysWith: { first, _ in first })
        let coffeesByDay = Dictionary(grouping: coffees) { calendar.startOfDay(for: $0.date) }
        let coffeePairs = coffeesByDay.compactMap { day, records -> (Double, Double)? in
            guard let latest = records.max(by: { $0.date < $1.date }), let sleep = sleepByNight[day] else { return nil }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            return (latest.date.timeIntervalSince(noon) / 60, sleep.sleepMinutes)
        }

        let workoutsByDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.start) }
        let exercisePairs = morningRMSSD.compactMap { morning -> (Double, Double)? in
            guard let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: morning.date)) else { return nil }
            let minutes = (workoutsByDay[previous] ?? []).map(\.durationMinutes).reduce(0, +)
            return (minutes, morning.median)
        }

        let morningByDay = Dictionary(morningRMSSD.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
        let sleepPairs = sleeps.compactMap { sleep -> (Double, Double)? in
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: sleep.nightDate)),
                  let morning = morningByDay[next] else { return nil }
            return (sleep.sleepMinutes, morning.median)
        }

        var workdayValues: [Double] = []
        var nonWorkdayValues: [Double] = []
        for sample in dailyRMSSD {
            switch commuteStatusByDay[calendar.startOfDay(for: sample.date)] ?? .unclassified {
            case .workday: workdayValues.append(sample.median)
            case .nonWorkday: nonWorkdayValues.append(sample.median)
            case .unclassified: break
            }
        }

        return [
            correlationResult(type: .coffeeAndSleep, pairs: coffeePairs, unit: "건"),
            correlationResult(type: .exerciseAndMorningRMSSD, pairs: exercisePairs, unit: "일"),
            correlationResult(type: .sleepAndMorningRMSSD, pairs: sleepPairs, unit: "일"),
            commuteResult(workday: workdayValues, nonWorkday: nonWorkdayValues)
        ].sorted { lhs, rhs in
            lhs.strength.rank == rhs.strength.rank
                ? lhs.sampleCount > rhs.sampleCount
                : lhs.strength.rank > rhs.strength.rank
        }
    }

    private static func correlationResult(type: UnsolvedCaseType, pairs: [(Double, Double)], unit: String) -> UnsolvedCaseResult {
        let correlation = HRVStatistics.pearsonCorrelation(pairs)
        let strength = evidenceStrength(correlation: correlation, sampleCount: pairs.count)
        let correlationText = correlation.map { " · r \(String(format: "%.2f", $0))" } ?? ""
        return UnsolvedCaseResult(
            type: type,
            sampleCount: pairs.count,
            correlation: correlation,
            strength: strength,
            summary: "증거 \(pairs.count)\(unit) · \(strength.label)\(correlationText)",
            detail: correlation.map { "상관계수 \(String(format: "%.2f", $0))" } ?? "비교할 데이터가 더 필요해요.",
            insight: strength == .strong || strength == .moderate
                ? correlation.map {
                    insightTemplate(for: type).make(
                        isPositive: $0 > 0,
                        sampleCount: pairs.count,
                        unit: unit,
                        strength: strength
                    )
                }
                : nil
        )
    }

    private static func commuteResult(workday: [Double], nonWorkday: [Double]) -> UnsolvedCaseResult {
        let workMedian = workday.isEmpty ? nil : HRVStatistics.median(workday)
        let nonWorkMedian = nonWorkday.isEmpty ? nil : HRVStatistics.median(nonWorkday)
        let percent = workMedian.flatMap { work in nonWorkMedian.flatMap { $0 > 0 ? (work - $0) / $0 * 100 : nil } }
        let enough = workday.count >= LongTermCaseConfiguration.minimumSampleCount && nonWorkday.count >= LongTermCaseConfiguration.minimumSampleCount
        let strength: EvidenceStrength = enough ? strengthForDifference(percent) : .insufficient
        let detail = percent.map { "출근일이 비출근일보다 중앙값 기준 \(Int(abs($0).rounded()))% \($0 < 0 ? "낮아요." : "높아요.")" }
            ?? "명확히 분류된 출근일과 비출근일 데이터가 더 필요해요."
        return UnsolvedCaseResult(
            type: .commuteAndRMSSD,
            sampleCount: workday.count + nonWorkday.count,
            correlation: nil,
            strength: strength,
            summary: "출근 \(workday.count)일 / 비출근 \(nonWorkday.count)일 · \(strength.label)",
            detail: detail,
            insight: strength == .strong || strength == .moderate
                ? percent.map {
                    insightTemplate(for: .commuteAndRMSSD).make(
                        isPositive: $0 > 0,
                        sampleCount: workday.count + nonWorkday.count,
                        unit: "일",
                        strength: strength
                    )
                }
                : nil
        )
    }

    private static func insightTemplate(for type: UnsolvedCaseType) -> CaseInsightTemplate {
        switch type {
        case .coffeeAndSleep:
            CaseInsightTemplate(
                positivePattern: "커피를 늦게 마신 날일수록 수면시간이 길어지는 패턴이 반복되었어요.",
                negativePattern: "커피를 늦게 마신 날일수록 수면시간이 짧아지는 패턴이 반복되었어요.",
                positiveInterpretation: "현재 데이터에서는 늦은 커피가 수면 감소의 유력한 용의자로 보이지 않아요.",
                negativeInterpretation: "현재 가장 유력한 용의자는 늦은 커피입니다."
            )
        case .exerciseAndMorningRMSSD:
            CaseInsightTemplate(
                positivePattern: "운동량이 많았던 다음 날에는 오전 rMSSD가 높아지는 패턴이 반복되었어요.",
                negativePattern: "운동량이 많았던 다음 날에는 오전 rMSSD가 낮아지는 패턴이 반복되었어요.",
                positiveInterpretation: "운동이 회복에 도움이 되었을 가능성이 있습니다.",
                negativeInterpretation: "운동량이 회복에 부담을 주는 요인인지 계속 조사해 볼게요."
            )
        case .sleepAndMorningRMSSD:
            CaseInsightTemplate(
                positivePattern: "수면시간이 길었던 다음 날에는 오전 rMSSD가 높게 나타나는 경향이 있었어요.",
                negativePattern: "수면시간이 길었던 다음 날에는 오전 rMSSD가 낮게 나타나는 경향이 있었어요.",
                positiveInterpretation: "충분한 수면이 회복에 도움이 되었을 가능성이 있습니다.",
                negativeInterpretation: "수면시간 외의 다른 단서가 있는지 조사를 계속할게요."
            )
        case .commuteAndRMSSD:
            CaseInsightTemplate(
                positivePattern: "출근한 날에는 rMSSD가 비출근일보다 높은 패턴이 반복되었어요.",
                negativePattern: "출근한 날에는 rMSSD가 비출근일보다 낮은 패턴이 반복되었어요.",
                positiveInterpretation: "현재 데이터에서는 출근이 회복에 부담을 주는 용의자로 보이지 않아요.",
                negativeInterpretation: "출근이 몸에 부담을 주는 요인인지 계속 조사해 볼게요."
            )
        }
    }

    private static func evidenceStrength(correlation: Double?, sampleCount: Int) -> EvidenceStrength {
        guard sampleCount >= LongTermCaseConfiguration.minimumSampleCount, let correlation else { return .insufficient }
        switch abs(correlation) {
        case ..<0.2: return .none
        case ..<0.4: return .weak
        case ..<0.6: return .moderate
        default: return .strong
        }
    }

    private static func strengthForDifference(_ percent: Double?) -> EvidenceStrength {
        guard let percent else { return .insufficient }
        switch abs(percent) {
        case ..<5: return .none
        case ..<10: return .weak
        case ..<20: return .moderate
        default: return .strong
        }
    }
}

enum TodayBriefingClueBuilder {
    static func build(
        samples: [(date: Date, value: Double)],
        baseline: RMSSDRecentBaseline,
        notes: [(date: Date, note: String)],
        day: Date = Date()
    ) -> [BriefingClue] {
        let calendar = Calendar.current
        let candidates = samples.compactMap {
            sample -> (sample: (date: Date, value: Double), ratio: Double, direction: RMSSDThresholdDirection)? in
            guard calendar.isDate(sample.date, inSameDayAs: day) else { return nil }
            guard !baseline.sleepRanges.contains(where: { sample.date >= $0.start && sample.date <= $0.end }) else {
                return nil
            }
            guard let median = RMSSDThreshold.periodMedian(at: sample.date, baseline: baseline), median > 0 else {
                return nil
            }
            guard let direction = RMSSDThreshold.direction(value: sample.value, median: median) else { return nil }
            return (sample, sample.value / median, direction)
        }
        guard !candidates.isEmpty else { return [] }

        return candidates
            .sorted { abs($0.ratio - 1) > abs($1.ratio - 1) }
            .prefix(DailyBriefingConfiguration.maximumTodayClues)
            .map { candidate in
                switch candidate.direction {
                case .low:
                    clue(label: "스트레스가 높은 순간", candidate: candidate, notes: notes, type: .negative)
                case .high:
                    clue(label: "스트레스가 낮은 순간", candidate: candidate, notes: notes, type: .positive)
                }
            }
    }

    private static func clue(
        label: String,
        candidate: (sample: (date: Date, value: Double), ratio: Double, direction: RMSSDThresholdDirection),
        notes: [(date: Date, note: String)],
        type: ClueType
    ) -> BriefingClue {
        let matchedNote = notes
            .filter { abs($0.date.timeIntervalSince(candidate.sample.date)) <= 5 * 60 }
            .min { abs($0.date.timeIntervalSince(candidate.sample.date)) < abs($1.date.timeIntervalSince(candidate.sample.date)) }?
            .note.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = matchedNote.flatMap { $0.isEmpty ? nil : $0 }
            .map { ", \($0)" }
            ?? ", HRV \(Int(candidate.sample.value.rounded()))"
        return BriefingClue(
            category: .hrv,
            type: type,
            message: "\(label): \(DateKey.timeString(from: candidate.sample.date))\(suffix)",
            severity: abs(candidate.ratio - 1),
            occurredAt: candidate.sample.date
        )
    }
}

struct DailyBriefingInput {
    // 수면
    let sleepDurationChangeMinutes: Double
    let awakeDurationChangeMinutes: Double
    let awakeRatioChangePercent: Double
    let longestContinuousSleepChangeMinutes: Double

    // HRV
    let rmssdValue: Double?
    let rmssdChangePercent: Double?
    let rmssdPercentile30Days: Double?

    // 수면 전에 기록된 행동과 일정
    let coffees: [BriefingCoffeeRecord]
    let workouts: [BriefingWorkoutRecord]
    let schedules: [BriefingScheduleRecord]

    // 해당 브리핑 관찰 구간의 rMSSD 측정에 사용자가 남긴 메모
    let hrvNotes: [BriefingHRVNote]
}

struct BriefingCoffeeRecord {
    let date: Date
}

struct BriefingWorkoutRecord {
    let start: Date
    let durationMinutes: Double
    let intensity: Double?
}

struct BriefingScheduleRecord {
    let start: Date
    let end: Date
}

struct BriefingHRVNote {
    let date: Date
    let note: String
    let direction: RMSSDThresholdDirection
}

struct BriefingClue: Identifiable {
    let id = UUID()
    let category: ClueCategory
    let type: ClueType
    let message: String
    let severity: Double
    let occurredAt: Date?
}

enum ClueCategory: Equatable {
    case sleep
    case hrv
    case coffee
    case exercise
    case schedule
    case note
}

enum ClueType: Equatable {
    case positive
    case negative
    case neutral
}

enum BriefingCaseType {
    case fragmentedSleep
    case shortSleep
    case strongRecovery
    case lowRMSSD
    case ordinaryNight

    var title: String {
        switch self {
        case .fragmentedSleep: "수면이 끊긴 밤"
        case .shortSleep: "짧은 수면 사건"
        case .strongRecovery: "회복의 흔적"
        case .lowRMSSD: "낮아진 회복 신호"
        case .ordinaryNight: "평범한 밤의 기록"
        }
    }
}

enum BriefingCaseDetector {
    static func detect(from input: DailyBriefingInput) -> BriefingCaseType {
        if input.awakeRatioChangePercent >= 30,
           input.longestContinuousSleepChangeMinutes <= -30 {
            return .fragmentedSleep
        }
        if input.sleepDurationChangeMinutes <= -60 { return .shortSleep }
        if input.awakeRatioChangePercent <= -20,
           input.longestContinuousSleepChangeMinutes >= 30,
           (input.rmssdChangePercent ?? 0) >= 10 {
            return .strongRecovery
        }
        if (input.rmssdChangePercent ?? 0) <= -20 { return .lowRMSSD }
        return .ordinaryNight
    }
}

enum SleepClueBuilder {
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        var clues: [BriefingClue] = []

        if abs(input.sleepDurationChangeMinutes) >= DailyBriefingConfiguration.sleepDurationThresholdMinutes {
            clues.append(clue(
                label: "수면",
                value: input.sleepDurationChangeMinutes,
                threshold: 60,
                isPositive: input.sleepDurationChangeMinutes > 0
            ))
        }
        if abs(input.awakeDurationChangeMinutes) >= DailyBriefingConfiguration.awakeDurationThresholdMinutes {
            clues.append(clue(
                label: "총 각성",
                value: input.awakeDurationChangeMinutes,
                threshold: 10,
                isPositive: input.awakeDurationChangeMinutes < 0
            ))
        }
        if abs(input.longestContinuousSleepChangeMinutes) >= DailyBriefingConfiguration.continuousSleepThresholdMinutes {
            clues.append(clue(
                label: "연속 수면",
                value: input.longestContinuousSleepChangeMinutes,
                threshold: 30,
                isPositive: input.longestContinuousSleepChangeMinutes > 0
            ))
        }
        return clues
    }

    private static func clue(label: String, value: Double, threshold: Double, isPositive: Bool) -> BriefingClue {
        BriefingClue(
            category: .sleep,
            type: isPositive ? .positive : .negative,
            message: "\(label) \(signedInteger(value))분",
            severity: abs(value) / threshold,
            occurredAt: nil
        )
    }
}

enum HRVClueBuilder {
    // hrvTerm: 연구자/관리자에게는 "rMSSD", 일반 사용자에게는 "HRV"(AuthViewModel.hrvTerm) — 홈
    // 화면은 누구나 보므로 호출부가 역할에 맞는 용어를 넘겨준다.
    static func build(from input: DailyBriefingInput, hrvTerm: String) -> [BriefingClue] {
        var clues: [BriefingClue] = []
        if let change = input.rmssdChangePercent,
           change.isFinite,
           abs(change) >= DailyBriefingConfiguration.rmssdChangeThresholdPercent {
            clues.append(BriefingClue(
                category: .hrv,
                type: change > 0 ? .positive : .negative,
                message: "\(hrvTerm) \(signedInteger(change))%",
                severity: abs(change) / DailyBriefingConfiguration.rmssdChangeThresholdPercent,
                occurredAt: nil
            ))
        }
        if let percentile = input.rmssdPercentile30Days {
            if percentile <= 10 {
                clues.append(BriefingClue(
                    category: .hrv,
                    type: .negative,
                    message: "\(hrvTerm) 최근 30일 하위 10%",
                    severity: 2.5,
                    occurredAt: nil
                ))
            } else if percentile >= 90 {
                clues.append(BriefingClue(
                    category: .hrv,
                    type: .positive,
                    message: "\(hrvTerm) 최근 30일 상위 10%",
                    severity: 2.5,
                    occurredAt: nil
                ))
            }
        }
        return clues
    }
}

enum CoffeeClueBuilder {
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        guard let latest = input.coffees.max(by: { $0.date < $1.date }) else { return [] }
        let hour = Calendar.current.component(.hour, from: latest.date)
        guard hour >= DailyBriefingConfiguration.lateCoffeeStartHour else { return [] }
        return [BriefingClue(
            category: .coffee,
            type: .neutral,
            message: "마지막 커피 \(hour)시",
            severity: hour >= DailyBriefingConfiguration.veryLateCoffeeStartHour ? 2 : 1.2,
            occurredAt: latest.date
        )]
    }
}

enum WorkoutClueBuilder {
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        guard !input.workouts.isEmpty else { return [] }
        let totalMinutes = input.workouts.map(\.durationMinutes).reduce(0, +)
        let maximumIntensity = input.workouts.compactMap(\.intensity).max()
        let occurredAt = input.workouts.max(by: { $0.start < $1.start })?.start

        if let maximumIntensity,
           maximumIntensity >= DailyBriefingConfiguration.highIntensityWorkoutMinimum {
            return [BriefingClue(
                category: .exercise,
                type: .neutral,
                message: "고강도 운동 \(Int(totalMinutes.rounded()))분",
                severity: 1.8,
                occurredAt: occurredAt
            )]
        }
        guard totalMinutes >= DailyBriefingConfiguration.minimumWorkoutMinutes else { return [] }
        return [BriefingClue(
            category: .exercise,
            type: .neutral,
            message: "운동 \(Int(totalMinutes.rounded()))분",
            severity: 1,
            occurredAt: occurredAt
        )]
    }
}

enum ScheduleClueBuilder {
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        let longSchedules = input.schedules.filter {
            $0.end.timeIntervalSince($0.start) >= DailyBriefingConfiguration.longScheduleMinimumMinutes * 60
        }
        guard !longSchedules.isEmpty else { return [] }
        let totalHours = longSchedules.map { $0.end.timeIntervalSince($0.start) / 3_600 }.reduce(0, +)

        if totalHours >= DailyBriefingConfiguration.busyScheduleMinimumHours {
            return [BriefingClue(
                category: .schedule,
                type: .neutral,
                message: "긴 일정 \(Int(totalHours.rounded()))시간",
                severity: totalHours / 4,
                occurredAt: longSchedules.map(\.start).min()
            )]
        }
        if longSchedules.count >= DailyBriefingConfiguration.manySchedulesMinimumCount {
            return [BriefingClue(
                category: .schedule,
                type: .neutral,
                message: "주요 일정 \(longSchedules.count)건",
                severity: Double(longSchedules.count) / 2,
                occurredAt: longSchedules.map(\.start).min()
            )]
        }
        return []
    }
}

enum NoteClueBuilder {
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        guard let note = input.hrvNotes.max(by: { $0.date < $1.date }) else { return [] }
        let trimmed = note.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let moment = switch note.direction {
        case .high: "스트레스가 낮은 순간"
        case .low: "스트레스가 높은 순간"
        }
        let time = DateKey.timeString(from: note.date)
        return [BriefingClue(
            category: .note,
            type: .neutral,
            message: "\(moment): \(time), \(shortened(trimmed))",
            severity: 2.2,
            occurredAt: note.date
        )]
    }

    private static func shortened(_ text: String) -> String {
        let maximumLength = DailyBriefingConfiguration.noteMaximumLength
        guard text.count > maximumLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maximumLength)
        return "\(text[..<end])…"
    }
}

enum BriefingClueBuilder {
    static func build(from input: DailyBriefingInput, hrvTerm: String) -> [BriefingClue] {
        let candidates = SleepClueBuilder.build(from: input)
            + HRVClueBuilder.build(from: input, hrvTerm: hrvTerm)
            + NoteClueBuilder.build(from: input)
            + WorkoutClueBuilder.build(from: input)
            + CoffeeClueBuilder.build(from: input)
            + ScheduleClueBuilder.build(from: input)

        let sorted = candidates.sorted { lhs, rhs in
            lhs.severity == rhs.severity
                ? categoryPriority(lhs.category) > categoryPriority(rhs.category)
                : lhs.severity > rhs.severity
        }
        var unique: [BriefingClue] = []
        for clue in sorted where !isDuplicate(clue, in: unique) {
            unique.append(clue)
        }
        return Array(unique.prefix(DailyBriefingConfiguration.maximumDisplayedClues))
    }

    private static func categoryPriority(_ category: ClueCategory) -> Int {
        switch category {
        case .note: 6
        case .sleep: 5
        case .hrv: 4
        case .exercise: 3
        case .coffee: 2
        case .schedule: 1
        }
    }

    private static func isDuplicate(_ clue: BriefingClue, in existing: [BriefingClue]) -> Bool {
        if existing.contains(where: { $0.message == clue.message }) { return true }
        // 변화율과 30일 백분위가 동시에 후보가 되면 더 중요한 HRV 단서 하나만 남긴다.
        return clue.category == .hrv && existing.contains(where: { $0.category == .hrv })
    }
}

private func signedInteger(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : "-"
    return "\(sign)\(Int(abs(value).rounded()))"
}
