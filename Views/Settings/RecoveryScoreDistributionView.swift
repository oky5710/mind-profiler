import SwiftUI

// 회복 지수 배점(baseScore/pointsPerZScore) 후보를 실제 기기의 rMSSD·수면 데이터로 검증하기 위한
// 진단 전용 화면 — 화면에 보여줄 점수 자체가 아니라, combinedZ(RecoveryScoreBuilder 참고)를 최근
// 며칠치 실제로 계산해서 여러 배점 후보에 각각 대입했을 때 분포가 어떻게 달라지는지 보여준다.
// 릴리스 빌드에는 없고, 개발 중에 배점을 튜닝할 때 admin이 직접 실행해서 확인하는 용도다.
struct RecoveryScoreDistributionView: View {
    @State private var isRunning = false
    @State private var resultText: String?
    @State private var errorText: String?

    private static let dayCount = 90
    private static let historyDayCount = 30
    // (기준점, 편차 1당 배점, 표시 이름) — 첫 항목은 이전(50 + z×15) 배점과 비교하기 위한 참고용.
    private static let candidates: [(base: Double, perZ: Double, label: String)] = [
        (50, 15, "이전 (50 + z×15)"),
        (75, 8, "제안 A (75 + z×8)"),
        (75, 10, "현재 적용값 (75 + z×10)"),
        (75, 12, "제안 C (75 + z×12)"),
    ]

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await run() }
                } label: {
                    if isRunning {
                        ProgressView()
                    } else {
                        Text("분포 분석 실행")
                    }
                }
                .disabled(isRunning)
            } footer: {
                Text("최근 \(Self.dayCount)일치 원시 rMSSD·수면 데이터를 다시 조회해서, 실제 하루하루의 편차(z)에 배점 후보 4개를 각각 대입했을 때 점수 분포가 어떻게 달라지는지 보여줍니다. 화면에 남는 회복 지수 값은 바꾸지 않아요.")
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
            }

            if let resultText {
                Section("결과") {
                    Text(resultText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("회복 지수 분포 확인")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        isRunning = true
        errorText = nil
        resultText = nil
        defer { isRunning = false }

        do {
            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)
            let fetchStart = calendar.date(
                byAdding: .day,
                value: -(Self.dayCount + Self.historyDayCount + 1),
                to: today
            ) ?? today

            try await HealthKitService.requestAuthorization()
            async let samplesTask = RMSSDLocalStore.shared.samples(start: fetchStart, end: now)
            async let sleepTask = HealthKitService.fetchSleepStageSamples(start: fetchStart, end: now)
            let (samples, sleepSamples) = try await (samplesTask, sleepTask)
            let sleepRanges = SleepAnalysisService.buildSleepRanges(sleepSamples)

            var zScores: [Double] = []
            for offset in 0..<Self.dayCount {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let historyStart = calendar.date(byAdding: .day, value: -Self.historyDayCount, to: day) ?? day
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let windowSamples = samples.filter { $0.date >= historyStart && $0.date < dayEnd }
                if let z = RecoveryScoreBuilder.combinedZScore(samples: windowSamples, sleepRanges: sleepRanges, day: day) {
                    zScores.append(z)
                }
            }

            guard !zScores.isEmpty else {
                errorText = "회복 지수를 계산할 수 있는 날이 없어요 — 이 기간의 원시 rMSSD 데이터가 부족합니다."
                return
            }

            resultText = Self.formatResult(zScores: zScores)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private static func formatResult(zScores: [Double]) -> String {
        var lines: [String] = ["분석된 날: \(zScores.count)일 / \(dayCount)일"]

        for candidate in candidates {
            let scores = zScores.map {
                score(forZ: $0, base: candidate.base, perZ: candidate.perZ)
            }
            let sorted = scores.sorted()
            let median = sorted[sorted.count / 2]
            let inTargetRange = scores.filter { $0 >= 60 && $0 <= 90 }.count
            let percentInTargetRange = Int((Double(inTargetRange) / Double(scores.count) * 100).rounded())
            let lowClampCount = scores.filter { $0 <= 0 }.count
            let highClampCount = scores.filter { $0 >= 100 }.count

            lines.append("")
            lines.append("[\(candidate.label)]")
            lines.append("  범위 \(sorted.first ?? 0)~\(sorted.last ?? 0) · 중앙값 \(median)")
            lines.append("  60~90점 비율: \(percentInTargetRange)%")
            if lowClampCount > 0 || highClampCount > 0 {
                lines.append("  0점/100점에 눌린 날: \(lowClampCount)일 / \(highClampCount)일")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func score(forZ z: Double, base: Double, perZ: Double) -> Int {
        Int((base + z * perZ).clamped(to: 0...100).rounded())
    }
}

#Preview {
    NavigationStack {
        RecoveryScoreDistributionView()
    }
}
