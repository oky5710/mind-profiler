import Foundation

// rMSSD 등 시계열 값에 대한 순수 통계 계산 — 여러 ViewModel(HRVAnalysisViewModel, ReportViewModel)이
// 공유해서 쓴다.
enum HRVStatistics {
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        }
        return sorted[count / 2]
    }

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // 표본 표준편차(n-1로 나눔) — 값이 1개 이하면 편차를 정의할 수 없어 0으로 둔다.
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        let sumSquaredDiffs = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        return (sumSquaredDiffs / Double(values.count - 1)).squareRoot()
    }

    // 변동계수(CV) = 표준편차 ÷ 평균 × 100.
    static func coefficientOfVariation(_ values: [Double]) -> Double? {
        let m = mean(values)
        guard m != 0 else { return nil }
        return standardDeviation(values) / m * 100
    }

    // 선형 보간 방식(Type 7, numpy 기본값과 동일)의 백분위수 — 값이 비어 있으면 0.
    static func quartiles(_ values: [Double]) -> (q1: Double, median: Double, q3: Double) {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return (0, 0, 0) }
        return (percentile(sorted, 0.25), percentile(sorted, 0.5), percentile(sorted, 0.75))
    }

    private static func percentile(_ sortedValues: [Double], _ fraction: Double) -> Double {
        guard sortedValues.count > 1 else { return sortedValues.first ?? 0 }
        let rank = fraction * Double(sortedValues.count - 1)
        let lowerIndex = Int(rank)
        let upperIndex = min(lowerIndex + 1, sortedValues.count - 1)
        let interpolation = rank - Double(lowerIndex)
        return sortedValues[lowerIndex] + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * interpolation
    }

    static func dailyMedian(_ samples: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
        var groups: [Date: [Double]] = [:]
        for sample in samples {
            groups[Calendar.current.startOfDay(for: sample.date), default: []].append(sample.value)
        }
        return groups
            .map { (day, values) in (date: day, value: median(values)) }
            .sorted { $0.date < $1.date }
    }

    // Pearson 상관계수: r = (nΣxy - ΣxΣy) / sqrt((nΣx² - (Σx)²)(nΣy² - (Σy)²))
    static func pearsonCorrelation(_ pairs: [(Double, Double)]) -> Double? {
        guard pairs.count >= 2 else { return nil }

        let xs = pairs.map(\.0)
        let ys = pairs.map(\.1)
        let count = Double(pairs.count)

        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXSquared = xs.reduce(0) { $0 + $1 * $1 }
        let sumYSquared = ys.reduce(0) { $0 + $1 * $1 }
        let sumProduct = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }

        let numerator = count * sumProduct - sumX * sumY
        let denominator = ((count * sumXSquared - sumX * sumX) * (count * sumYSquared - sumY * sumY)).squareRoot()
        guard denominator != 0 else { return nil }
        return numerator / denominator
    }

    // 상관계수 절댓값을 사람이 읽을 말로 — 정확한 임계값보다 대략적인 느낌을 전달하려는 용도.
    static func correlationStrengthLabel(_ r: Double) -> String {
        switch abs(r) {
        case 0.6...: "강함"
        case 0.4..<0.6: "중간"
        case 0.2..<0.4: "약함"
        default: "거의 없음"
        }
    }
}
