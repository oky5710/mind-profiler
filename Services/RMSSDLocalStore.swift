import Foundation
import SwiftData

@MainActor
final class RMSSDLocalStore {
    static let shared = RMSSDLocalStore()
    static let calculationVersion = 1
    static let aggregationVersion = 1

    private let container: ModelContainer
    private var isPerformingOperation = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        do {
            let schema = Schema([RMSSDMeasurement.self, DailyRMSSDSummary.self])
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appending(path: "RMSSDLocalCache", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (directory as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            let configuration = ModelConfiguration(
                "RMSSDLocalCache",
                schema: schema,
                url: directory.appending(path: "rmssd.store"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("로컬 rMSSD 저장소를 만들 수 없습니다: \(error.localizedDescription)")
        }
    }

    func samples(start: Date?, end: Date?) async throws -> [(date: Date, value: Double)] {
        await acquireOperation()
        defer { releaseOperation() }
        let queryStart = start ?? .distantPast
        let queryEnd = end ?? Date()
        try await synchronize(start: queryStart, end: queryEnd)
        return try measurements(start: queryStart, end: queryEnd).map { ($0.measuredAt, $0.value) }
    }

    func dailySummaries(start: Date, end: Date) async throws -> [DailyRMSSDSummaryDTO] {
        await acquireOperation()
        defer { releaseOperation() }
        try await synchronize(start: start, end: end)
        try await rebuildSummaries(start: start, end: end)
        return try fetchSummaries(start: start, end: end)
    }

    // @MainActor는 컨텍스트 접근 자체를 보호하지만 await 지점에서는 다른 요청이 재진입할 수 있다.
    // 동기화와 집계를 하나의 작업 단위로 직렬화해 동일 UUID의 중복 계산과 경쟁 저장을 함께 막는다.
    private func acquireOperation() async {
        guard isPerformingOperation else {
            isPerformingOperation = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            isPerformingOperation = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }

    private func synchronize(start: Date, end: Date) async throws {
        let cached = try measurements(start: start, end: end)
        let currentUUIDs = Set(cached.filter { $0.calculationVersion == Self.calculationVersion }.map(\.healthKitUUID))
        let batch = try await HealthKitService.fetchCalculatedRMSSDBatch(
            start: start == .distantPast ? nil : start,
            end: end,
            excluding: currentUUIDs
        )
        let context = ModelContext(container)

        for result in batch.calculated {
            let uuid = result.healthKitUUID
            let descriptor = FetchDescriptor<RMSSDMeasurement>(predicate: #Predicate { $0.healthKitUUID == uuid })
            if let existing = try context.fetch(descriptor).first {
                existing.measuredAt = result.measuredAt
                existing.value = result.value
                existing.validIntervalCount = result.validIntervalCount
                existing.totalBeatCount = result.totalBeatCount
                existing.calculationVersion = Self.calculationVersion
                existing.updatedAt = .now
            } else {
                context.insert(RMSSDMeasurement(
                    healthKitUUID: uuid,
                    measuredAt: result.measuredAt,
                    value: result.value,
                    validIntervalCount: result.validIntervalCount,
                    totalBeatCount: result.totalBeatCount,
                    calculationVersion: Self.calculationVersion
                ))
            }
        }

        // 조회 범위에서 HealthKit에 더 이상 존재하지 않는 측정은 로컬 캐시에서도 제거한다.
        for item in cached where !batch.healthKitUUIDs.contains(item.healthKitUUID) {
            let uuid = item.healthKitUUID
            let descriptor = FetchDescriptor<RMSSDMeasurement>(predicate: #Predicate { $0.healthKitUUID == uuid })
            if let stored = try context.fetch(descriptor).first { context.delete(stored) }
        }
        if context.hasChanges { try context.save() }
    }

    private func measurements(start: Date, end: Date) throws -> [RMSSDMeasurementDTO] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<RMSSDMeasurement>(
            predicate: #Predicate { $0.measuredAt >= start && $0.measuredAt <= end },
            sortBy: [SortDescriptor(\.measuredAt)]
        )
        descriptor.includePendingChanges = false
        return try context.fetch(descriptor).map {
            RMSSDMeasurementDTO(
                healthKitUUID: $0.healthKitUUID,
                measuredAt: $0.measuredAt,
                value: $0.value,
                validIntervalCount: $0.validIntervalCount,
                totalBeatCount: $0.totalBeatCount,
                calculationVersion: $0.calculationVersion
            )
        }
    }

    private func rebuildSummaries(start: Date, end: Date) async throws {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        let sleepEnd = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? end
        let sleepSamples = try await HealthKitService.fetchSleepStageSamples(start: sleepStart, end: sleepEnd)
        let sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)
        let context = ModelContext(container)
        var day = firstDay

        while day <= lastDay {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { break }
            let values = try measurements(start: day, end: dayEnd.addingTimeInterval(-0.001))
            let daySleepRanges = sleepRanges.filter { $0.end > day && $0.start < dayEnd }
            let wakeTime = daySleepRanges
                .filter { SleepAnalysisService.nightLabel(for: $0.start) < day }
                .map(\.end)
                .max()
            let sleepValues = values.filter { sample in
                daySleepRanges.contains { sample.measuredAt >= $0.start && sample.measuredAt <= $0.end }
            }.map(\.value)
            let morningValues = values.filter { sample in
                guard let wakeTime, sample.measuredAt >= wakeTime, sample.measuredAt < noon else { return false }
                return !daySleepRanges.contains { sample.measuredAt >= $0.start && sample.measuredAt <= $0.end }
            }.map(\.value)
            let afternoonValues = values.filter { sample in
                sample.measuredAt >= noon
                    && !daySleepRanges.contains { sample.measuredAt >= $0.start && sample.measuredAt <= $0.end }
            }.map(\.value)

            let key = DateKey.string(from: day)
            let descriptor = FetchDescriptor<DailyRMSSDSummary>(predicate: #Predicate { $0.dayKey == key })
            let summary = try context.fetch(descriptor).first
                ?? DailyRMSSDSummary(dayKey: key, date: day, aggregationVersion: Self.aggregationVersion)
            if summary.modelContext == nil { context.insert(summary) }
            summary.wholeDayMedian = values.isEmpty ? nil : HRVStatistics.median(values.map(\.value))
            summary.wholeDayCount = values.count
            summary.sleepMedian = sleepValues.isEmpty ? nil : HRVStatistics.median(sleepValues)
            summary.sleepCount = sleepValues.count
            summary.morningMedian = morningValues.isEmpty ? nil : HRVStatistics.median(morningValues)
            summary.morningCount = morningValues.count
            summary.afternoonMedian = afternoonValues.isEmpty ? nil : HRVStatistics.median(afternoonValues)
            summary.afternoonCount = afternoonValues.count
            summary.aggregationVersion = Self.aggregationVersion
            summary.updatedAt = .now
            day = dayEnd
        }
        if context.hasChanges { try context.save() }
    }

    private func fetchSummaries(start: Date, end: Date) throws -> [DailyRMSSDSummaryDTO] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DailyRMSSDSummary>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).map {
            DailyRMSSDSummaryDTO(
                date: $0.date,
                wholeDayMedian: $0.wholeDayMedian,
                wholeDayCount: $0.wholeDayCount,
                sleepMedian: $0.sleepMedian,
                sleepCount: $0.sleepCount,
                morningMedian: $0.morningMedian,
                morningCount: $0.morningCount,
                afternoonMedian: $0.afternoonMedian,
                afternoonCount: $0.afternoonCount
            )
        }
    }
}
