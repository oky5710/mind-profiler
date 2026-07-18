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

    private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

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
            ]
        )
    }

    // rMSSD보다 덜 중요한 참고값이라 화면에서는 옅게(회색 반투명) 보여주기만 한다.
    static func fetchSDNNSamples() async throws -> [(date: Date, value: Double)] {
        try await fetchQuantitySamples(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli)
        )
    }

    // HealthKit은 SDNN만 직접 주고 rMSSD는 없음 — 애플워치가 SDNN을 잴 때 같이 남기는 원시 박동
    // 시리즈(HKHeartbeatSeriesSample)에서 박동 간 간격을 직접 계산해서 구한다.
    static func fetchRMSSDSamples() async throws -> [(date: Date, value: Double)] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.heartbeatSeries()],
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

    static func fetchWorkoutRanges() async throws -> [(start: Date, end: Date)] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ranges = (samples as? [HKWorkout] ?? []).map { workout in
                    (start: workout.startDate, end: workout.endDate)
                }
                continuation.resume(returning: ranges)
            }
            store.execute(query)
        }
    }

    static func fetchSleepRanges() async throws -> [(start: Date, end: Date)] {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ranges = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .map { (start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: ranges)
            }
            store.execute(query)
        }
    }

    private static func fetchQuantitySamples(
        type: HKQuantityType,
        unit: HKUnit
    ) async throws -> [(date: Date, value: Double)] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
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
}
