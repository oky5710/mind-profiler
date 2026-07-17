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

                    BarChartCard(title: "기분", data: viewModel.moodSeries, color: moodColor, yDomain: 0...5)
                    BarChartCard(title: "커피", data: viewModel.coffeeSeries, color: coffeeColor, yDomain: nil)
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
}

#Preview {
    StatisticsView()
}
