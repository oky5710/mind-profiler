import SwiftUI

// SettingsView의 NavigationStack 안에서 열리며, 진입 시 전체 기간 데이터를 한 번 분석한다.
struct CorrelationAnalysisView: View {
    @State private var viewModel = CorrelationAnalysisViewModel()

    var body: some View {
        List {
            Section {
                if viewModel.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("전체 기간 분석 중...")
                    }
                } else if viewModel.hasAnalyzed {
                    correlationTable

                    Button("다시 분석") {
                        Task { await viewModel.analyze() }
                    }
                } else {
                    Button("상관계수 분석") {
                        Task { await viewModel.analyze() }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("rMSSD와 상관계수")
            } footer: {
                Text("저장된 전체 기간에서 변수별 유효 날짜와 일별 rMSSD 중앙값을 짝지어 Pearson 상관계수를 계산해요. 2시간 이하의 수면은 수면 항목에서 제외해요.")
            }
        }
        .navigationTitle("상관계수 분석")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !viewModel.hasAnalyzed else { return }
            await viewModel.analyze()
        }
    }

    private var correlationTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                tableText("변수", isHeader: true)
                tableText("상관계수", isHeader: true)
                tableText("강도", isHeader: true)
                tableText("표본 수", isHeader: true)
            }
            divider

            ForEach(viewModel.findings) { finding in
                GridRow {
                    tableText(finding.variable)
                    tableText(finding.coefficient.map { String(format: "%.2f", $0) } ?? "—")
                    tableText(finding.strengthLabel ?? "—")
                    tableText("\(finding.sampleCount)")
                }
                divider
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableText(_ value: String, isHeader: Bool = false) -> some View {
        Text(value)
            .font(Typography.caption2)
            .foregroundStyle(isHeader ? .secondary : .primary)
    }

    private var divider: some View {
        Divider()
            .gridCellColumns(4)
    }
}

#Preview {
    NavigationStack {
        CorrelationAnalysisView()
    }
}
