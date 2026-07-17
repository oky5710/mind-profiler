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

    static func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: [hrvType])
    }

    static func fetchHRVSamples(daysBack: Int = 180) async throws -> [(date: Date, value: Double)] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.notAvailable
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let points = (samples as? [HKQuantitySample] ?? []).map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: .secondUnit(with: .milli)))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }
}
