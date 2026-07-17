import Charts
import SwiftUI

struct StatisticsView: View {
    @State private var viewModel = StatisticsViewModel()

    private let moodColor = Color(red: 0.9569, green: 0.2471, blue: 0.3686) // #f43f5e
    private let coffeeColor = Color(red: 0.5725, green: 0.2510, blue: 0.0549) // #92400e

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.isLoading && viewModel.moodSeries.isEmpty && viewModel.coffeeSeries.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    chartSection(title: "기분", data: viewModel.moodSeries, color: moodColor, yDomain: 0...5)
                    chartSection(title: "커피", data: viewModel.coffeeSeries, color: coffeeColor, yDomain: nil)
                }
                .padding()
            }
            .navigationTitle("통계")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private func chartSection(
        title: String,
        data: [StatisticsViewModel.DailyValue],
        color: Color,
        yDomain: ClosedRange<Double>?
    ) -> some View {
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

#Preview {
    StatisticsView()
}
