import Foundation

// "오늘의 패턴" 차트의 급격한 rMSSD 저하 강조와 백그라운드 급격한 변화 알림이 정확히 같은 기준을
// 쓰도록 공유한다 — 따로 구현하면 화면에는 안 뜨는데 알림은 오는(혹은 그 반대) 식으로 어긋난다.
enum RMSSDThresholdDirection: String, Codable {
    case low = "LOW"
    case high = "HIGH"
}

enum RMSSDThreshold {
    // 기존 "오늘의 패턴" 차트에서 쓰던 급격한 저하 기준(최근 30일 중앙값의 50% 미만)을 그대로 쓴다.
    static let lowMultiplier = 0.5
    // 낮음 기준과 대칭되는 새 기준 — 중앙값의 150% 이상이면 급격히 높아진 것으로 본다.
    static let highMultiplier = 1.5

    static func direction(value: Double, median: Double) -> RMSSDThresholdDirection? {
        if value < median * lowMultiplier { return .low }
        if value >= median * highMultiplier { return .high }
        return nil
    }

    static func fetchRecentThirtyDayMedian(asOf now: Date = Date()) async throws -> Double? {
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let samples = try await HealthKitService.fetchRMSSDSamples(start: thirtyDaysAgo, end: now)
        return samples.isEmpty ? nil : HRVStatistics.median(samples.map(\.value))
    }
}
