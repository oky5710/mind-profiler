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
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }

        try await store.requestAuthorization(
            toShare: [],
            read: [hrvType, HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis), HKSeriesType.heartbeat()]
        )
    }

    static func fetchHRVSamples() async throws -> [(date: Date, value: Double)] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }
        return try await fetchQuantitySamples(type: hrvType, unit: .secondUnit(with: .milli))
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

    // 시리즈 중간에 워치를 벗는 등 끊긴 구간(precededByGap)의 앞뒤 박동은 연속된 간격이 아니므로 계산에서 뺀다.
    private static func rMSSD(for series: HKHeartbeatSeriesSample) async throws -> Double? {
        let descriptor = HKHeartbeatSeriesQueryDescriptor(series)
        var previousTime: TimeInterval?
        var squaredDiffs: [Double] = []

        for try await beat in descriptor.results(for: store) {
            defer { previousTime = beat.timeIntervalSinceStart }
            if let previousTime, !beat.precededByGap {
                let diffMs = (beat.timeIntervalSinceStart - previousTime) * 1000
                squaredDiffs.append(diffMs * diffMs)
            }
        }

        guard !squaredDiffs.isEmpty else { return nil }
        return (squaredDiffs.reduce(0, +) / Double(squaredDiffs.count)).squareRoot()
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
