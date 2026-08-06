import Foundation
import SwiftData

@MainActor
final class RMSSDLocalStore {
    static let shared = RMSSDLocalStore()
    static let calculationVersion = 1
    // 수면 세션 병합 기준이 1시간에서 2시간으로 바뀌어 과거 시간대 분류도 다시 만들어야 한다.
    static let aggregationVersion = 2

    private let container: ModelContainer
    private var isPerformingOperation = false
    private var operationWaiters: [OperationWaiter] = []

    private struct OperationWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    // 디스크 저장소를 만들 수 없을 때(손상된 파일, 디스크 공간 부족 등) 이번 실행에서는 캐시가
    // 유지되지 않고 매번 다시 계산되지만, 최소한 앱은 계속 쓸 수 있다는 걸 호출부가 알 수 있게 남긴다.
    private(set) var isUsingInMemoryFallback = false

    private init() {
        let schema = Schema([RMSSDMeasurement.self, DailyRMSSDSummary.self])
        if let onDiskContainer = Self.makeOnDiskContainer(schema: schema) {
            container = onDiskContainer
        } else {
            // 디스크 저장소는 그냥 다시 계산해서 채우는 캐시일 뿐이라, 열 수 없다고 앱을 못 쓰게
            // 만들 이유가 없다 — 메모리 전용 컨테이너로 내려가 이번 실행 동안만 캐시 없이 동작한다.
            // 스키마 자체는 고정돼 있어 메모리 전용 생성은 실패할 일이 없다.
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            isUsingInMemoryFallback = true
        }
    }

    private static func makeOnDiskContainer(schema: Schema, allowsRetryAfterReset: Bool = true) -> ModelContainer? {
        do {
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
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard allowsRetryAfterReset else { return nil }
            // 손상된 저장소일 수 있으니 한 번 비우고 새로 만들어본다 — 디스크가 아예 꽉 찼거나
            // 디렉토리 권한 문제라면 이 재시도도 실패하고, 그때는 메모리 전용으로 내려간다.
            // 어차피 다시 계산해서 채우는 캐시라 지우고 다시 만드는 쪽이 안전하다.
            removeOnDiskStore()
            return makeOnDiskContainer(schema: schema, allowsRetryAfterReset: false)
        }
    }

    private static func removeOnDiskStore() {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let directory = support.appending(path: "RMSSDLocalCache", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
    }

    func samples(start: Date?, end: Date?) async throws -> [(date: Date, value: Double)] {
        try await acquireOperation()
        defer { releaseOperation() }
        let queryStart = start ?? .distantPast
        let queryEnd = end ?? Date()
        _ = try await synchronize(start: queryStart, end: queryEnd)
        return try measurements(start: queryStart, end: queryEnd).map { ($0.measuredAt, $0.value) }
    }

    func dailySummaries(start: Date, end: Date) async throws -> [DailyRMSSDSummaryDTO] {
        (try await window(start: start, end: end)).summaries
    }

    func window(start: Date, end: Date) async throws -> RMSSDWindowDTO {
        try await acquireOperation()
        defer { releaseOperation() }
        let affectedDays = try await synchronize(start: start, end: end)
        let cachedMeasurements = try measurements(start: start, end: end)
        let daysToRebuild = try summaryDaysToRebuild(
            start: start,
            end: end,
            measurements: cachedMeasurements,
            affectedDays: affectedDays
        )
        if !daysToRebuild.isEmpty {
            try await rebuildSummaries(days: daysToRebuild, measurements: cachedMeasurements)
        }
        return RMSSDWindowDTO(
            measurements: cachedMeasurements,
            summaries: try fetchSummaries(start: start, end: end)
        )
    }

    // @MainActor는 컨텍스트 접근 자체를 보호하지만 await 지점에서는 다른 요청이 재진입할 수 있다.
    // 동기화와 집계를 하나의 작업 단위로 직렬화해 동일 UUID의 중복 계산과 경쟁 저장을 함께 막는다.
    private func acquireOperation() async throws {
        try Task.checkCancellation()
        guard isPerformingOperation else {
            isPerformingOperation = true
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operationWaiters.append(OperationWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            // onCancel은 대기 중인 스레드/컨텍스트에서 곧바로(동기적으로) 호출될 수 있어, MainActor에
            // 격리된 operationWaiters를 직접 건드릴 수 없다 — MainActor 작업으로 넘겨서 처리한다.
            Task { @MainActor in self.cancelWaiter(id: id) }
        }

        // 대기열에서는 정상적으로 깨어났지만, 그 사이(막 깨어난 바로 그 순간) 취소됐다면 — 위
        // cancelWaiter가 이미 대기열에서 빼내 처리한 경우와 경합해 이 시점엔 이미 늦었을 수 있다 —
        // 실제 작업은 하지 않고 바로 다음 대기자에게 넘긴다.
        if Task.isCancelled {
            releaseOperation()
            throw CancellationError()
        }
    }

    // 대기 중 취소된 요청은 자기 차례가 올 때까지 기다렸다가 그제서야 취소를 반영하는 대신, 대기열에서
    // 바로 빼서 실패로 깨운다 — 그래야 뒤에 줄 서 있는(아직 취소되지 않은) 요청이 그만큼 더 기다리지
    // 않는다. releaseOperation()의 removeFirst()가 이미 이 대기자를 가져갔다면(경합) 여기서는 더
    // 할 일이 없다.
    private func cancelWaiter(id: UUID) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == id }) else { return }
        operationWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            isPerformingOperation = false
        } else {
            operationWaiters.removeFirst().continuation.resume()
        }
    }

    private func synchronize(start: Date, end: Date) async throws -> Set<Date> {
        let calendar = Calendar.current
        let cached = try measurements(start: start, end: end)
        let currentUUIDs = Set(cached.filter { $0.calculationVersion == Self.calculationVersion }.map(\.healthKitUUID))
        let batch = try await HealthKitService.fetchCalculatedRMSSDBatch(
            start: start == .distantPast ? nil : start,
            end: end,
            excluding: currentUUIDs
        )
        let context = ModelContext(container)
        var affectedDays = Set<Date>()

        for result in batch.calculated {
            affectedDays.insert(calendar.startOfDay(for: result.measuredAt))
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
            affectedDays.insert(calendar.startOfDay(for: item.measuredAt))
            let uuid = item.healthKitUUID
            let descriptor = FetchDescriptor<RMSSDMeasurement>(predicate: #Predicate { $0.healthKitUUID == uuid })
            if let stored = try context.fetch(descriptor).first { context.delete(stored) }
        }
        if context.hasChanges { try context.save() }
        return affectedDays
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

    private func summaryDaysToRebuild(
        start: Date,
        end: Date,
        measurements: [RMSSDMeasurementDTO],
        affectedDays: Set<Date>
    ) throws -> Set<Date> {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DailyRMSSDSummary>(
            predicate: #Predicate { $0.date >= firstDay && $0.date <= lastDay }
        )
        let currentSummaryDays = Set(try context.fetch(descriptor).compactMap {
            $0.aggregationVersion == Self.aggregationVersion ? calendar.startOfDay(for: $0.date) : nil
        })
        let measurementDays = Set(measurements.map { calendar.startOfDay(for: $0.measuredAt) })
        var days = affectedDays.union(measurementDays.subtracting(currentSummaryDays))

        // 수면 데이터는 늦게 확정될 수 있으므로 오늘과 어제만 매번 다시 분류한다.
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        for recentDay in [yesterday, today] where recentDay >= firstDay && recentDay <= lastDay {
            days.insert(recentDay)
        }
        return days
    }

    private func rebuildSummaries(
        days: Set<Date>,
        measurements: [RMSSDMeasurementDTO]
    ) async throws {
        guard let firstDay = days.min(), let lastDay = days.max() else { return }
        let calendar = Calendar.current
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        let sleepEnd = calendar.date(byAdding: .day, value: 2, to: lastDay) ?? lastDay
        let sleepSamples = try await HealthKitService.fetchSleepStageSamples(start: sleepStart, end: sleepEnd)
        let sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<DailyRMSSDSummary>(
            predicate: #Predicate { $0.date >= firstDay && $0.date <= lastDay }
        )
        var summariesByKey = Dictionary(
            try context.fetch(descriptor).map { ($0.dayKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let valuesByDay = Dictionary(grouping: measurements) {
            calendar.startOfDay(for: $0.measuredAt)
        }

        for day in days.sorted() {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { continue }
            let values = valuesByDay[day] ?? []
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
            let summary = summariesByKey[key]
                ?? DailyRMSSDSummary(dayKey: key, date: day, aggregationVersion: Self.aggregationVersion)
            if summary.modelContext == nil {
                context.insert(summary)
                summariesByKey[key] = summary
            }
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
