import Foundation

// 최근 한 달치 원시 RR(박동 간격) 데이터를 필터링 없이 CSV로 내보낸다 — 다른 앱과 rMSSD 값을
// 직접 비교/검증하고 싶을 때 원본 데이터 자체를 볼 수 있게 한다.
@MainActor
@Observable
final class RRIntervalExportViewModel {
    private(set) var beats: [HealthKitService.RawBeat] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func export() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await HealthKitService.requestAuthorization()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
            beats = try await HealthKitService.fetchRawRRIntervals(start: start, end: end)
            if beats.isEmpty {
                errorMessage = "최근 한 달 동안 원시 박동 데이터가 없어요."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var csvString: String {
        let formatter = ISO8601DateFormatter()
        var lines = ["series_start,beat_time,interval_ms,preceded_by_gap"]
        lines += beats.map { beat in
            let intervalText = beat.intervalMs.map { String(format: "%.1f", $0) } ?? ""
            return "\(formatter.string(from: beat.seriesStart)),\(formatter.string(from: beat.beatDate))," +
                "\(intervalText),\(beat.precededByGap)"
        }
        return lines.joined(separator: "\n")
    }

    func writeCSVToTemporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mindprofiler_rr_intervals_last30days.csv")
        try csvString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
