import Charts
import SwiftUI

struct BarChartCard: View {
    let title: String
    let data: [DailyValue]
    let color: Color
    let yDomain: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)

            if data.isEmpty {
                Text("기록된 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("날짜", point.date, unit: .day),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(color)
                }
                .frame(height: 160)
                .chartYScale(domain: yDomain ?? 0...max(1, data.map(\.value).max() ?? 1))
            }
        }
    }
}
