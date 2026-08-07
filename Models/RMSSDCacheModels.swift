import Foundation
import SwiftData

@Model
final class RMSSDMeasurement {
    @Attribute(.unique) var healthKitUUID: String
    var measuredAt: Date
    var value: Double
    var validIntervalCount: Int
    var totalBeatCount: Int
    var calculationVersion: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        healthKitUUID: String,
        measuredAt: Date,
        value: Double,
        validIntervalCount: Int,
        totalBeatCount: Int,
        calculationVersion: Int
    ) {
        self.healthKitUUID = healthKitUUID
        self.measuredAt = measuredAt
        self.value = value
        self.validIntervalCount = validIntervalCount
        self.totalBeatCount = totalBeatCount
        self.calculationVersion = calculationVersion
        createdAt = .now
        updatedAt = .now
    }
}

@Model
final class DailyRMSSDSummary {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var wholeDayMedian: Double?
    var wholeDayCount: Int
    var sleepMedian: Double?
    var sleepCount: Int
    var morningMedian: Double?
    var morningCount: Int
    var afternoonMedian: Double?
    var afternoonCount: Int
    var aggregationVersion: Int
    var updatedAt: Date

    init(dayKey: String, date: Date, aggregationVersion: Int) {
        self.dayKey = dayKey
        self.date = date
        wholeDayCount = 0
        sleepCount = 0
        morningCount = 0
        afternoonCount = 0
        self.aggregationVersion = aggregationVersion
        updatedAt = .now
    }
}

@Model
final class MonthlyRMSSDSummary {
    @Attribute(.unique) var monthKey: String
    var monthStart: Date
    var q1: Double
    var median: Double
    var q3: Double
    var coefficientOfVariation: Double?
    var dayCount: Int
    var aggregationVersion: Int
    var updatedAt: Date

    init(monthKey: String, monthStart: Date, aggregationVersion: Int) {
        self.monthKey = monthKey
        self.monthStart = monthStart
        q1 = 0
        median = 0
        q3 = 0
        coefficientOfVariation = nil
        dayCount = 0
        self.aggregationVersion = aggregationVersion
        updatedAt = .now
    }
}

struct RMSSDMeasurementDTO: Sendable {
    let healthKitUUID: String
    let measuredAt: Date
    let value: Double
    let validIntervalCount: Int
    let totalBeatCount: Int
    let calculationVersion: Int
}

struct DailyRMSSDSummaryDTO: Sendable {
    let date: Date
    let wholeDayMedian: Double?
    let wholeDayCount: Int
    let sleepMedian: Double?
    let sleepCount: Int
    let morningMedian: Double?
    let morningCount: Int
    let afternoonMedian: Double?
    let afternoonCount: Int
}

struct MonthlyRMSSDSummaryDTO: Sendable {
    let monthStart: Date
    let q1: Double
    let median: Double
    let q3: Double
    let coefficientOfVariation: Double?
    let dayCount: Int
}

struct RMSSDWindowDTO: Sendable {
    let measurements: [RMSSDMeasurementDTO]
    let summaries: [DailyRMSSDSummaryDTO]
    let monthlySummaries: [MonthlyRMSSDSummaryDTO]
}
