import Foundation
import HealthKit

enum HealthKitError: Error, LocalizedError {
    case notAvailable

    var errorDescription: String? {
        "이 기기에서는 건강 데이터를 사용할 수 없어요."
    }
}

enum HealthKitService {
    private static let store = HKHealthStore()

    // HealthKit은 숫자 "수면 점수"를 공개 API로 제공하지 않아(애플워치 자체 수면 앱의 내부 지표),
    // 대신 탭했을 때 보여줄 수 있는 건 단계별(코어/깊은/렘) 시간 구성이다.
    enum SleepStage: String, CaseIterable {
        case core, deep, rem, unspecified

        fileprivate init?(categoryValue: Int) {
            switch categoryValue {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: self = .core
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: self = .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: self = .rem
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: self = .unspecified
            default: return nil
            }
        }
    }

    // 운동 상세 패널에 보여줄 종목 이름. HKWorkoutActivityType은 80개가 넘어서 자주 쓰는 종목만
    // 매핑하고, 나머지는 뭉뚱그려 "기타 운동"으로 보여준다.
    static func workoutActivityTypeDisplayName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "달리기"
        case .walking: "걷기"
        case .cycling: "사이클"
        case .swimming: "수영"
        case .yoga: "요가"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "근력 운동"
        case .coreTraining: "코어 운동"
        case .elliptical: "일립티컬"
        case .rowing: "로잉"
        case .stairClimbing: "계단 오르기"
        case .hiking: "하이킹"
        case .dance: "댄스"
        case .highIntensityIntervalTraining: "고강도 인터벌(HIIT)"
        case .mixedCardio, .cardioDance: "유산소"
        case .pilates: "필라테스"
        case .basketball: "농구"
        case .soccer: "축구"
        case .tennis: "테니스"
        case .golf: "골프"
        default: "기타 운동"
        }
    }

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        // HealthKit 제약: HKSeriesType.heartbeat() 읽기 권한은 반드시 SDNN 권한과 같이 요청해야 한다
        // ("Authorization for HKQuantityTypeIdentifierHeartRateVariabilitySDNN should also be requested
        // when requesting authorization to read HKDataTypeIdentifierHeartbeatSeries" — 안 하면 즉시 크래시).
        // SDNN 값 자체도 rMSSD와 비교해서 보여주는 참고용 회색 라인(시간별 전용)으로 다시 쓴다.
        try await store.requestAuthorization(
            toShare: [],
            read: [
                HKObjectType.workoutType(),
                HKCategoryType(.sleepAnalysis),
                HKSeriesType.heartbeat(),
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.restingHeartRate),
            ]
        )
    }

    // rMSSD보다 덜 중요한 참고값이라 화면에서는 옅게(회색 반투명) 보여주기만 한다.
    // start/end를 주면 그 구간만 조회한다 — "오늘의 패턴"이 보이는 구간의 5배만 불러오는 용도.
    // 기본값(nil)은 기존처럼 전체 이력을 조회한다(보고서 등 다른 화면은 그대로 전체가 필요).
    static func fetchSDNNSamples(start: Date? = nil, end: Date? = nil) async throws -> [(date: Date, value: Double)] {
        try await fetchQuantitySamples(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli),
            start: start,
            end: end
        )
    }

    // 보고서의 기간 요약(심박수 중앙값)용. 원시 heartRate 전체 샘플의 중앙값은 운동/활동 중 측정치가
    // 섞여서 지나치게 높게 나온다 — 애플워치가 하루 한 번쯤 계산해 두는 안정시 심박수
    // (restingHeartRate)를 대신 쓴다.
    static func fetchRestingHeartRateSamples() async throws -> [(date: Date, value: Double)] {
        try await fetchQuantitySamples(
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute())
        )
    }

    // 같은 HRV 측정에서 나온 SDNN 샘플과 원시 박동 시리즈(rMSSD 계산용)는 시작 시각이 거의 동일하다
    // (몇 초 이내) — 그 시각으로 짝지어서 같은 측정의 SDNN·rMSSD 쌍을 만든다. 두 지표의 상관관계
    // 분석(Settings 화면의 "SDNN vs rMSSD 분석")에 쓴다.
    private static let pairingTolerance: TimeInterval = 5

    static func fetchSDNNRMSSDPairs() async throws -> [(date: Date, sdnn: Double, rmssd: Double)] {
        async let sdnnSamples = fetchSDNNSamples()
        async let rmssdSamples = fetchRMSSDSamples()
        let (sdnn, rmssd) = try await (sdnnSamples, rmssdSamples)
        return pairSDNNAndRMSSD(sdnn: sdnn, rmssd: rmssd)
    }

    // fetchSDNNRMSSDPairs()의 짝짓기 로직만 뺀 순수 함수 — 이미 두 샘플을 따로 가지고 있는 호출부
    // (ReportViewModel)는 fetchSDNNRMSSDPairs()를 다시 부르면 rMSSD/SDNN을 통째로 한 번 더
    // 조회하게 되므로, 이미 가진 배열을 그대로 넘겨서 짝만 짓는다.
    static func pairSDNNAndRMSSD(
        sdnn: [(date: Date, value: Double)],
        rmssd: [(date: Date, value: Double)]
    ) -> [(date: Date, sdnn: Double, rmssd: Double)] {
        let sortedSDNN = sdnn.sorted { $0.date < $1.date }
        var pairs: [(date: Date, sdnn: Double, rmssd: Double)] = []
        var sdnnIndex = 0

        for point in rmssd.sorted(by: { $0.date < $1.date }) {
            while sdnnIndex < sortedSDNN.count, sortedSDNN[sdnnIndex].date < point.date.addingTimeInterval(-pairingTolerance) {
                sdnnIndex += 1
            }
            guard sdnnIndex < sortedSDNN.count else { break }
            if abs(sortedSDNN[sdnnIndex].date.timeIntervalSince(point.date)) <= pairingTolerance {
                pairs.append((date: point.date, sdnn: sortedSDNN[sdnnIndex].value, rmssd: point.value))
            }
        }
        return pairs
    }

    // HealthKit은 SDNN만 직접 주고 rMSSD는 없음 — 애플워치가 SDNN을 잴 때 같이 남기는 원시 박동
    // 시리즈(HKHeartbeatSeriesSample)에서 박동 간 간격을 직접 계산해서 구한다.
    // start/end를 주면 그 구간의 시리즈만 조회한다 — 시리즈 하나하나가 박동 전체를 순회하는 값비싼
    // 계산이라, "오늘의 패턴"에서는 전체 이력이 아니라 보이는 구간의 5배만 계산하면 된다.
    static func fetchRMSSDSamples(start: Date? = nil, end: Date? = nil) async throws -> [(date: Date, value: Double)] {
        let predicate: HKSamplePredicate<HKHeartbeatSeriesSample>
        if let start, let end {
            predicate = .heartbeatSeries(HKQuery.predicateForSamples(withStart: start, end: end, options: []))
        } else {
            predicate = .heartbeatSeries()
        }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let seriesSamples = try await descriptor.result(for: store)

        return try await withThrowingTaskGroup(of: (date: Date, value: Double)?.self) { group in
            for series in seriesSamples {
                group.addTask {
                    guard let value = try await rMSSD(for: series) else { return nil }
                    return (date: series.startDate, value: value)
                }
            }

            var results: [(date: Date, value: Double)] = []
            for try await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results.sorted { $0.date < $1.date }
        }
    }

    // 30~200bpm(300~2000ms) 밖의 간격은 센서 오검출(놓친 박동/중복 검출)로 보고 버린다.
    // rMSSD는 간격 차이를 제곱해서 평균 내기 때문에, 이런 이상치 하나만 껴 있어도 값이 크게 튄다.
    private static let plausibleIntervalRangeMs: ClosedRange<Double> = 300...2000
    // 절대 범위 안에 있어도 직전 간격보다 25% 넘게 튀면(HRV 아티팩트 교정에서 흔히 쓰는 기준) 그 변화는
    // 진짜 HRV가 아니라 오검출일 가능성이 커서 제외한다. 다만 뒤 박동들은 새 기준(interval)으로 계속 비교한다.
    // (20%는 운동 직후·호흡 조절처럼 진짜로 변동이 큰 구간까지 과하게 걸러낼 수 있어 25%로 완화함)
    private static let maxRelativeIntervalChange = 0.25

    // rMSSD는 "연속된 박동 간격(RR interval)들의 차이"를 제곱해서 평균 낸 값의 제곱근이다 —
    // RR 간격 자체를 제곱하는 게 아니라, RR(i+1) - RR(i)를 제곱해야 한다. 시리즈 중간에 워치를
    // 벗는 등 끊긴 구간(precededByGap)에서는 그 앞뒤 RR 간격을 이어붙이면 안 되므로 리셋한다.
    private static func rMSSD(for series: HKHeartbeatSeriesSample) async throws -> Double? {
        let descriptor = HKHeartbeatSeriesQueryDescriptor(series)
        var previousBeatTime: TimeInterval?
        var previousInterval: Double?
        var sumOfSquaredDiffs = 0.0
        var diffCount = 0

        for try await beat in descriptor.results(for: store) {
            defer { previousBeatTime = beat.timeIntervalSinceStart }

            guard let previousBeatTime, !beat.precededByGap else {
                previousInterval = nil
                continue
            }

            let interval = (beat.timeIntervalSinceStart - previousBeatTime) * 1000
            guard plausibleIntervalRangeMs.contains(interval) else {
                previousInterval = nil
                continue
            }

            if let previousInterval {
                let diff = interval - previousInterval
                if abs(diff) / previousInterval <= maxRelativeIntervalChange {
                    sumOfSquaredDiffs += diff * diff
                    diffCount += 1
                }
            }
            previousInterval = interval
        }

        guard diffCount > 0 else { return nil }
        return (sumOfSquaredDiffs / Double(diffCount)).squareRoot()
    }

    #if DEBUG
    private struct DebugBeat {
        let date: Date
        // 시리즈 경계를 이어붙일 때 원본 HealthKit 플래그를 덮어써야 할 때가 있어서(예: 두 시리즈를
        // 이어붙여 계산할 때 그 경계는 gap이 아닌 것으로 취급) var로 둔다.
        var precededByGap: Bool
    }

    // 디버그 전용 — 어제(자정~자정) 원시 박동 시리즈를 전부 콘솔에 찍고(다른 앱이 계산한 rMSSD와
    // 비교 검증용), 이어서 rMSSD 계산 방식을 몇 가지 다르게 해본 값도 비교 출력한다. 앱 UI에는
    // 없고 MindProfilerApp의 #if DEBUG .task에서 한 번 호출된다.
    static func debugPrintRawRRIntervalsForToday() async {
        let calendar = Calendar.current
        guard
            let todayStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: Date())),
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)
        else { return }

        do {
            try await requestAuthorization()

            let predicate: HKSamplePredicate<HKHeartbeatSeriesSample> = .heartbeatSeries(
                HKQuery.predicateForSamples(withStart: yesterdayStart, end: todayStart, options: [])
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [predicate],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let seriesSamples = try await descriptor.result(for: store)

            guard !seriesSamples.isEmpty else {
                print("[RR 원시데이터] 어제(\(yesterdayStart) ~ \(todayStart)) 원시 박동 시리즈가 없어요.")
                return
            }

            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss.SSS"
            timeFormatter.locale = Locale(identifier: "en_US_POSIX")

            print("[RR 원시데이터] 어제 시리즈 \(seriesSamples.count)개")
            var beatsPerSeries: [[DebugBeat]] = []
            for (seriesIndex, series) in seriesSamples.enumerated() {
                print("--- 시리즈 \(seriesIndex + 1)/\(seriesSamples.count) 시작: \(timeFormatter.string(from: series.startDate)) ---")
                let queryDescriptor = HKHeartbeatSeriesQueryDescriptor(series)
                var previousBeatTime: TimeInterval?
                var beatIndex = 0
                var seriesBeats: [DebugBeat] = []

                for try await beat in queryDescriptor.results(for: store) {
                    let beatDate = series.startDate.addingTimeInterval(beat.timeIntervalSinceStart)
                    let rrText: String
                    if let previousBeatTime {
                        let intervalMs = (beat.timeIntervalSinceStart - previousBeatTime) * 1000
                        rrText = String(format: "%.1f", intervalMs) + "ms"
                    } else {
                        rrText = "-"
                    }
                    print("  [\(beatIndex)] \(timeFormatter.string(from: beatDate))  RR=\(rrText)  gap=\(beat.precededByGap)")
                    seriesBeats.append(DebugBeat(date: beatDate, precededByGap: beat.precededByGap))

                    previousBeatTime = beat.timeIntervalSinceStart
                    beatIndex += 1
                }
                print("  (시리즈 박동 수: \(beatIndex))")
                beatsPerSeries.append(seriesBeats)
            }

            debugCompareRMSSDVariants(beatsPerSeries: beatsPerSeries)
        } catch {
            print("[RR 원시데이터] 실패: \(error)")
        }
    }

    // rMSSD(for:)와 같은 계산이지만 임의의 DebugBeat 배열에 대해 동작하고, gap에서 리셋할지
    // (respectGap) 켜고 끌 수 있다.
    private static func rMSSD(
        from beats: [DebugBeat],
        respectGap: Bool,
        applyRangeFilter: Bool = true,
        applyRelativeFilter: Bool = true
    ) -> Double? {
        var previousDate: Date?
        var previousInterval: Double?
        var sumOfSquaredDiffs = 0.0
        var diffCount = 0

        for beat in beats {
            defer { previousDate = beat.date }

            guard let previousDate else {
                previousInterval = nil
                continue
            }
            if respectGap, beat.precededByGap {
                previousInterval = nil
                continue
            }

            let interval = beat.date.timeIntervalSince(previousDate) * 1000
            if applyRangeFilter {
                guard plausibleIntervalRangeMs.contains(interval) else {
                    previousInterval = nil
                    continue
                }
            }

            if let previousInterval {
                let diff = interval - previousInterval
                if !applyRelativeFilter || abs(diff) / previousInterval <= maxRelativeIntervalChange {
                    sumOfSquaredDiffs += diff * diff
                    diffCount += 1
                }
            }
            previousInterval = interval
        }

        guard diffCount > 0 else { return nil }
        return (sumOfSquaredDiffs / Double(diffCount)).squareRoot()
    }

    private static func fmt(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "nil"
    }

    // 요청받은 4가지 실험을 콘솔에 비교 출력한다: 연속 시리즈 2개 합쳐서 계산 / gap 무시하고 하루
    // 전체를 이어서 계산 / 30분 슬라이딩 윈도우 / 1시간 슬라이딩 윈도우. 다른 세 실험은 production과
    // 같은 필터(300~2000ms 범위 + 25% 상대변화)를 그대로 쓰고, "이어서 계산"만 gap 리셋을 끈다.
    private static func debugCompareRMSSDVariants(beatsPerSeries: [[DebugBeat]]) {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        print("\n[rMSSD 실험 비교]")

        // 1) 연속된 시리즈 2개를 합쳐서 계산 — 두 시리즈 경계는 gap이 아닌 것으로 본다.
        print("-- 1) 연속 시리즈 2개 합쳐서 계산 --")
        if beatsPerSeries.count < 2 {
            print("  시리즈가 2개 미만이라 비교할 수 없어요.")
        } else {
            for index in 0..<(beatsPerSeries.count - 1) {
                let first = beatsPerSeries[index]
                var second = beatsPerSeries[index + 1]
                guard !first.isEmpty, !second.isEmpty else { continue }
                second[0].precededByGap = false
                let merged = first + second

                let soloFirst = rMSSD(from: first, respectGap: true)
                let soloSecond = rMSSD(from: second, respectGap: true)
                let mergedValue = rMSSD(from: merged, respectGap: true)
                print(
                    "  시리즈 \(index + 1)+\(index + 2) (\(timeFormatter.string(from: first[0].date)) / " +
                        "\(timeFormatter.string(from: second[0].date))): " +
                        "개별=\(fmt(soloFirst))·\(fmt(soloSecond))  합쳐서=\(fmt(mergedValue))"
                )
            }
        }

        let allBeats = beatsPerSeries.flatMap { $0 }
        guard !allBeats.isEmpty else {
            print("[rMSSD 실험 비교] 박동 데이터가 없어 나머지 실험은 건너뜀.")
            return
        }

        // 2) gap을 무시하고 하루 전체를 하나로 이어서 계산.
        let ignoringGaps = rMSSD(from: allBeats, respectGap: false)
        let respectingGaps = rMSSD(from: allBeats, respectGap: true)
        print("-- 2) gap 무시하고 하루 전체 이어서 계산 --")
        print("  gap 무시=\(fmt(ignoringGaps))  (참고: gap 그대로 적용=\(fmt(respectingGaps)))")

        // 3), 4) 슬라이딩 윈도우 — 윈도우 폭의 1/3을 스텝으로 겹치면서 하루 전체를 훑는다.
        func slidingWindows(windowSeconds: TimeInterval) -> [(start: Date, rmssd: Double?, beatCount: Int)] {
            guard let firstDate = allBeats.first?.date, let lastDate = allBeats.last?.date else { return [] }
            let stepSeconds = windowSeconds / 3
            var results: [(Date, Double?, Int)] = []
            var windowStart = firstDate
            while windowStart < lastDate {
                let windowEnd = windowStart.addingTimeInterval(windowSeconds)
                let windowBeats = allBeats.filter { $0.date >= windowStart && $0.date < windowEnd }
                results.append((windowStart, rMSSD(from: windowBeats, respectGap: true), windowBeats.count))
                windowStart = windowStart.addingTimeInterval(stepSeconds)
            }
            return results
        }

        for (label, seconds) in [("30분", 30.0 * 60), ("1시간", 60.0 * 60)] {
            print("-- 3/4) \(label) 슬라이딩 윈도우 --")
            let windows = slidingWindows(windowSeconds: seconds)
            if windows.isEmpty {
                print("  데이터 없음")
            } else {
                for window in windows {
                    print("  \(timeFormatter.string(from: window.start))~  rMSSD=\(fmt(window.rmssd))  (박동 \(window.beatCount)개)")
                }
            }
        }
    }
    #endif

    static func fetchWorkoutRanges(start: Date? = nil, end: Date? = nil) async throws -> [
        (start: Date, end: Date, activityType: HKWorkoutActivityType, energyBurnedKcal: Double?, distanceMeters: Double?)
    ] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let predicate = dateRangePredicate(start: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ranges = (samples as? [HKWorkout] ?? []).map { workout in
                    (
                        start: workout.startDate,
                        end: workout.endDate,
                        activityType: workout.workoutActivityType,
                        // totalEnergyBurned/totalDistance는 iOS 18+ deprecated지만, 운동을 기록한 앱이
                        // HKWorkout 저장 시점에 같이 넣어둔 값을 그대로 읽는 거라 워크아웃 타입 권한
                        // 외에 별도 퀀티티 타입 권한이 필요 없다 — statistics(for:)로 바꾸면 활동
                        // 에너지/거리 퀀티티 타입 권한을 새로 요청해야 해서 이 방식을 그대로 쓴다.
                        energyBurnedKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        distanceMeters: workout.totalDistance?.doubleValue(for: .meter())
                    )
                }
                continuation.resume(returning: ranges)
            }
            store.execute(query)
        }
    }

    // 수면 단계(코어/깊은/렘/미상)가 붙은 상태로 원시 샘플을 그대로 반환한다 — 각성/침대에 누움 값은
    // SleepStage(categoryValue:)가 nil을 반환해 자동으로 걸러진다. 막대 구간 병합과 단계별 시간 집계는
    // 호출부(HRVAnalysisViewModel)에서 처리한다.
    static func fetchSleepStageSamples(start: Date? = nil, end: Date? = nil) async throws -> [(start: Date, end: Date, stage: SleepStage)] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let predicate = dateRangePredicate(start: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let stageSamples = (samples as? [HKCategorySample] ?? [])
                    .compactMap { sample -> (start: Date, end: Date, stage: SleepStage)? in
                        guard let stage = SleepStage(categoryValue: sample.value) else { return nil }
                        return (start: sample.startDate, end: sample.endDate, stage: stage)
                    }
                continuation.resume(returning: stageSamples)
            }
            store.execute(query)
        }
    }

    private static func fetchQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date? = nil,
        end: Date? = nil
    ) async throws -> [(date: Date, value: Double)] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let predicate = dateRangePredicate(start: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let points = (samples as? [HKQuantitySample] ?? []).map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    // start/end 둘 다 있을 때만 구간 predicate를 만들고, 아니면 nil(=제한 없음)을 그대로 둔다.
    private static func dateRangePredicate(start: Date?, end: Date?) -> NSPredicate? {
        guard let start, let end else { return nil }
        return HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }
}
