import Foundation

// HealthKit의 SDNN과 원시 박동에서 계산한 rMSSD가 실제로 얼마나 다른지 보여주는 분석.
// mind-record에는 없던, MindProfiler가 두 지표를 모두 갖고 있어서만 가능한 분석이다.
@MainActor
@Observable
final class HRVCorrelationViewModel {
    struct Stats {
        let sampleCount: Int
        let meanSDNN: Double
        let meanRMSSD: Double
        let ratio: Double
        let pearsonR: Double
    }

    private(set) var pairs: [(date: Date, sdnn: Double, rmssd: Double)] = []
    private(set) var stats: Stats?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // 산점도에서 아웃라이어를 찾아보려는 용도라 일단 최근 1년만 본다.
    var recentYearPairs: [(date: Date, sdnn: Double, rmssd: Double)] {
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        return pairs.filter { $0.date >= oneYearAgo }
    }

    func analyze() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await HealthKitService.requestAuthorization()
            pairs = try await HealthKitService.fetchSDNNRMSSDPairs()
            stats = Self.computeStats(pairs)
            if pairs.isEmpty {
                errorMessage = "같은 시각의 SDNN·rMSSD 쌍을 찾지 못했어요 (데이터가 없거나 측정 시각이 서로 안 맞음)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var csvString: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,sdnn_ms,rmssd_ms"]
        lines += pairs.map { pair in
            "\(formatter.string(from: pair.date)),\(pair.sdnn),\(pair.rmssd)"
        }
        return lines.joined(separator: "\n")
    }

    func writeCSVToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindprofiler_sdnn_rmssd.csv")
        try csvString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func computeStats(_ pairs: [(date: Date, sdnn: Double, rmssd: Double)]) -> Stats? {
        guard !pairs.isEmpty else { return nil }

        let sdnnValues = pairs.map(\.sdnn)
        let rmssdValues = pairs.map(\.rmssd)
        let count = Double(pairs.count)

        let meanSDNN = sdnnValues.reduce(0, +) / count
        let meanRMSSD = rmssdValues.reduce(0, +) / count
        let ratio = meanRMSSD == 0 ? 0 : meanSDNN / meanRMSSD

        // Pearson 상관계수: r = (nΣxy - ΣxΣy) / sqrt((nΣx² - (Σx)²)(nΣy² - (Σy)²))
        let sumSDNN = sdnnValues.reduce(0, +)
        let sumRMSSD = rmssdValues.reduce(0, +)
        let sumSDNNSquared = sdnnValues.reduce(0) { $0 + $1 * $1 }
        let sumRMSSDSquared = rmssdValues.reduce(0) { $0 + $1 * $1 }
        let sumProduct = zip(sdnnValues, rmssdValues).reduce(0) { $0 + $1.0 * $1.1 }

        let numerator = count * sumProduct - sumSDNN * sumRMSSD
        let denominator = ((count * sumSDNNSquared - sumSDNN * sumSDNN) * (count * sumRMSSDSquared - sumRMSSD * sumRMSSD)).squareRoot()
        let pearsonR = denominator == 0 ? 0 : numerator / denominator

        return Stats(
            sampleCount: pairs.count,
            meanSDNN: meanSDNN,
            meanRMSSD: meanRMSSD,
            ratio: ratio,
            pearsonR: pearsonR
        )
    }
}
