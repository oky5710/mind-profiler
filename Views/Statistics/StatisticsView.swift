import SwiftUI

struct StatisticsView: View {
    @State private var viewModel = StatisticsViewModel()

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

                    BarChartCard(title: "기분", data: viewModel.moodSeries, color: Theme.mood, yDomain: 0...5)
                    BarChartCard(title: "커피", data: viewModel.coffeeSeries, color: Theme.coffee, yDomain: nil)
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
