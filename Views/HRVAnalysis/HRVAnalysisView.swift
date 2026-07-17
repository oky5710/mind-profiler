import Charts
import SwiftUI

struct HRVAnalysisView: View {
    @State private var viewModel = HRVAnalysisViewModel()

    private let hrvLineColor = Color(red: 0.2314, green: 0.5098, blue: 0.9647) // #3b82f6
    private let sdnnColor = Color(red: 0.1333, green: 0.7725, blue: 0.3686) // #22c55e
    private let moodColor = Color(red: 0.9569, green: 0.2471, blue: 0.3686) // #f43f5e
    private let coffeeColor = Color(red: 0.5725, green: 0.2510, blue: 0.0549) // #92400e

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.isLoading && viewModel.examPoints.isEmpty && viewModel.wearableHRVSeries.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    hrvChart
                    BarChartCard(title: "기분", data: viewModel.moodSeries, color: moodColor, yDomain: 0...5)
                    BarChartCard(title: "커피", data: viewModel.coffeeSeries, color: coffeeColor, yDomain: nil)
                }
                .padding()
            }
            .navigationTitle("오늘의 패턴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .task {
            await viewModel.loadWearableHRVIfNeeded()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HRV 추이").font(.headline)

            if viewModel.wearableHRVSeries.isEmpty && viewModel.examPoints.isEmpty {
                Text("표시할 HRV 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(viewModel.wearableHRVSeries) { point in
                        LineMark(
                            x: .value("시간", point.date),
                            y: .value("HRV", point.value)
                        )
                        .foregroundStyle(hrvLineColor)
                    }

                    ForEach(viewModel.examPoints) { point in
                        PointMark(
                            x: .value("검사일", point.date),
                            y: .value("SDNN", point.sdnn)
                        )
                        .symbol(.triangle)
                        .foregroundStyle(sdnnColor)
                    }
                }
                .frame(height: 200)
            }

            if let healthKitErrorMessage = viewModel.healthKitErrorMessage {
                Text(healthKitErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if viewModel.wearableHRVSeries.isEmpty {
                Text("파란 선은 애플워치 HRV, 초록 세모는 검사 SDNN이에요. 애플워치 데이터가 없으면 세모만 보여요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HRVAnalysisView()
}
