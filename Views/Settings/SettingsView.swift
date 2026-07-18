import Charts
import SwiftUI

struct SettingsView: View {
    @State private var viewModel = HRVCorrelationViewModel()
    @State private var exportURL: URL?
    @State private var selectedPairDate: Date?

    private static let scatterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                            Text("분석 중...")
                        }
                    } else if let stats = viewModel.stats {
                        LabeledContent("샘플 수", value: "\(stats.sampleCount)개")
                        LabeledContent("평균 SDNN", value: String(format: "%.1f ms", stats.meanSDNN))
                        LabeledContent("평균 rMSSD", value: String(format: "%.1f ms", stats.meanRMSSD))
                        LabeledContent("SDNN / rMSSD", value: String(format: "%.2f", stats.ratio))
                        LabeledContent("상관계수 (Pearson r)", value: String(format: "%.2f", stats.pearsonR))

                        Button("다시 분석") {
                            exportURL = nil
                            Task { await viewModel.analyze() }
                        }
                    } else {
                        Button("SDNN·rMSSD 분석 실행") {
                            Task { await viewModel.analyze() }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("SDNN vs rMSSD 분석")
                } footer: {
                    Text("같은 측정 시각의 SDNN(HealthKit 제공)과 rMSSD(원시 박동에서 직접 계산) 쌍을 찾아 평균·비율·상관계수를 구해요.")
                }

                if !viewModel.pairs.isEmpty {
                    Section {
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("CSV로 공유하기", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button("CSV 내보내기 준비") {
                                exportURL = try? viewModel.writeCSVToTemporaryFile()
                            }
                        }
                    } header: {
                        Text("데이터 내보내기")
                    } footer: {
                        Text("측정 시각·SDNN·rMSSD 쌍 \(viewModel.pairs.count)개를 CSV로 내보내요.")
                    }
                }

                if !viewModel.recentYearPairs.isEmpty {
                    Section {
                        scatterChart
                        if let selectedPairDate {
                            Text(Self.scatterDateFormatter.string(from: selectedPairDate))
                                .font(.footnote)
                        } else {
                            Text("점을 탭하면 날짜가 표시돼요")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("산점도 (SDNN vs rMSSD, 최근 1년, 테스트용)")
                    }
                }
            }
            .navigationTitle("설정")
        }
    }

    // 아웃라이어 찾기용 테스트 화면이라 디자인은 신경 안 씀 — 기본 Chart 축 그대로 사용.
    private var scatterChart: some View {
        Chart(viewModel.recentYearPairs, id: \.date) { pair in
            PointMark(
                x: .value("SDNN", pair.sdnn),
                y: .value("rMSSD", pair.rmssd)
            )
            .foregroundStyle(selectedPairDate == pair.date ? .red : .blue)
        }
        .frame(height: 300)
        .chartXAxisLabel("SDNN (ms)")
        .chartYAxisLabel("rMSSD (ms)")
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin
                                let x = value.location.x - origin.x
                                let y = value.location.y - origin.y
                                guard let sdnnValue: Double = proxy.value(atX: x),
                                      let rmssdValue: Double = proxy.value(atY: y) else { return }
                                selectedPairDate = viewModel.recentYearPairs.min {
                                    let da = ($0.sdnn - sdnnValue) * ($0.sdnn - sdnnValue) + ($0.rmssd - rmssdValue) * ($0.rmssd - rmssdValue)
                                    let db = ($1.sdnn - sdnnValue) * ($1.sdnn - sdnnValue) + ($1.rmssd - rmssdValue) * ($1.rmssd - rmssdValue)
                                    return da < db
                                }?.date
                            }
                    )
            }
        }
    }
}

#Preview {
    SettingsView()
}
