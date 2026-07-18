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
            read: [hrvType, HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis)]
        )
    }

    static func fetchHRVSamples() async throws -> [(date: Date, value: Double)] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }
        return try await fetchQuantitySamples(type: hrvType, unit: .secondUnit(with: .milli))
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
