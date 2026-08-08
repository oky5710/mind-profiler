import SwiftUI

// 부모(SettingsView)가 이미 NavigationStack이라 여기서 새로 만들지 않는다 (AnalysisSettingsView와 동일 관례).
struct RRIntervalExportView: View {
    @State private var viewModel = RRIntervalExportViewModel()
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var viewModel = viewModel
        List {
            Section("기간") {
                Picker("기간", selection: $viewModel.selectedPeriod) {
                    ForEach(RRIntervalExportPeriod.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewModel.isLoading)
            }

            Section {
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                        Text("불러오는 중...")
                    }
                } else if !viewModel.beats.isEmpty {
                    LabeledContent("박동 수", value: "\(viewModel.beats.count)개")

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("CSV로 공유하기", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("CSV 내보내기 준비") {
                            exportURL = try? viewModel.writeCSVToTemporaryFile()
                        }
                    }

                    Button("다시 불러오기") {
                        exportURL = nil
                        Task { await viewModel.export() }
                    }
                } else {
                    Button(viewModel.selectedPeriod.loadButtonTitle) {
                        Task { await viewModel.export() }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("RR 데이터 내보내기")
            } footer: {
                Text("최근 30일 또는 HealthKit에 저장된 전체 기간의 원시 박동 간격(RR interval)을 " +
                    "필터링 없이 그대로 CSV로 내보내요. " +
                    "시리즈 시작 시각·박동 시각·간격(ms)·gap 여부가 각 줄에 담기고, 시각은 기기 로컬 " +
                    "시간대 기준이에요(UTC 아님).")
            }
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            exportURL = nil
            viewModel.resetResults()
        }
        .navigationTitle("RR 데이터 내보내기")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RRIntervalExportView()
    }
}
