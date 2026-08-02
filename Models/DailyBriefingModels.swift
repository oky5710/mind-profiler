import Foundation

private enum BriefingFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

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
    static let pointsPerZScore = 15.0
    static let minimumScore = 0.0
    static let maximumScore = 100.0
}

struct RecoveryScore {
    let value: Int

    var label: String {
        switch value {
        case 85...: "Excellent"
        case 70..<85: "Good"
        case 50..<70: "Fair"
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

        let combinedZ = zScores.reduce(0, +) / Double(zScores.count)
        let rawScore = 50 + combinedZ * RecoveryScoreConfiguration.pointsPerZScore
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
            ?? ", rMSSD \(Int(candidate.sample.value.rounded()))ms"
        return BriefingClue(
            category: .hrv,
            type: type,
            message: "\(label): \(BriefingFormatters.time.string(from: candidate.sample.date))\(suffix)",
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
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        var clues: [BriefingClue] = []
        if let change = input.rmssdChangePercent,
           change.isFinite,
           abs(change) >= DailyBriefingConfiguration.rmssdChangeThresholdPercent {
            clues.append(BriefingClue(
                category: .hrv,
                type: change > 0 ? .positive : .negative,
                message: "rMSSD \(signedInteger(change))%",
                severity: abs(change) / DailyBriefingConfiguration.rmssdChangeThresholdPercent,
                occurredAt: nil
            ))
        }
        if let percentile = input.rmssdPercentile30Days {
            if percentile <= 10 {
                clues.append(BriefingClue(
                    category: .hrv,
                    type: .negative,
                    message: "rMSSD 최근 30일 하위 10%",
                    severity: 2.5,
                    occurredAt: nil
                ))
            } else if percentile >= 90 {
                clues.append(BriefingClue(
                    category: .hrv,
                    type: .positive,
                    message: "rMSSD 최근 30일 상위 10%",
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
        let time = BriefingFormatters.time.string(from: note.date)
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
    static func build(from input: DailyBriefingInput) -> [BriefingClue] {
        let candidates = SleepClueBuilder.build(from: input)
            + HRVClueBuilder.build(from: input)
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
