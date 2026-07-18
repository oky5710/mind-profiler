import Charts
import SwiftUI

private enum HRVChartMode: String, CaseIterable {
    case hourly = "시간별"
    case daily = "일별"
    case monthly = "월별"

    var visibleDomain: TimeInterval {
        switch self {
        case .hourly: 24 * 60 * 60
        case .daily: 30 * 24 * 60 * 60
        case .monthly: 4 * 30 * 24 * 60 * 60
        }
    }
}

struct HRVAnalysisView: View {
    @State private var viewModel = HRVAnalysisViewModel()
    @State private var chartMode: HRVChartMode = .hourly
    @State private var hrvScrollPosition = Date().addingTimeInterval(-HRVChartMode.hourly.visibleDomain)
    @State private var dragAnchorPosition: Date?

    // hrvScrollPosition이 스크롤 중 계속 바뀌는데, 매 프레임 body가 다시 계산될 때마다
    // 전체 포인트를 다시 스캔하면 스크롤이 심하게 느려져서 모드/데이터가 바뀔 때만 갱신.
    @State private var cachedRange: (min: Double, max: Double) = (0, 100)

    private let hrvLineColor = Theme.hrvLine
    private let sdnnColor = Theme.sdnn
    private let exerciseColor = Theme.exercise
    private let sleepColor = Theme.sleep

    private static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var currentHRVPoints: [HRVAnalysisViewModel.HRVPoint] {
        switch chartMode {
        case .hourly: viewModel.wearableHRVPointsHourly
        case .daily: viewModel.wearableHRVPointsDaily
        case .monthly: []
        }
    }

    private var hasAnyLineChartData: Bool {
        !currentHRVPoints.isEmpty
            || !viewModel.examPoints.isEmpty
            || !viewModel.sleepRanges.isEmpty
            || !viewModel.exerciseRanges.isEmpty
    }

    private var hasGanttData: Bool {
        !viewModel.sleepRanges.isEmpty || !viewModel.exerciseRanges.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                hrvChart
                Spacer()
            }
            .padding()
            .navigationTitle("오늘의 패턴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
            recomputeRange()
        }
        .task {
            await viewModel.loadWearableHRVIfNeeded()
            recomputeRange()
        }
        .onChange(of: chartMode) { _, newMode in
            hrvScrollPosition = Date().addingTimeInterval(-newMode.visibleDomain)
            recomputeRange()
        }
        .refreshable {
            await viewModel.reload()
            recomputeRange()
        }
    }

    private func recomputeRange() {
        let values = currentHRVPoints.map(\.value) + viewModel.examPoints.map(\.sdnn)
        cachedRange = values.isEmpty ? (min: 0.0, max: 100.0) : (min: values.min()!, max: values.max()!)
    }

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HRV 추이").font(.headline)
                Spacer()
                Picker("보기 단위", selection: $chartMode) {
                    ForEach(HRVChartMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if (viewModel.isLoading || viewModel.isLoadingHealthKit) && !hasAnyLineChartData {
                HeartLoader(height: 200)
            } else if chartMode == .monthly {
                if viewModel.wearableHRVMonthlyStats.isEmpty && viewModel.examPoints.isEmpty {
                    Text("표시할 HRV 데이터가 없어요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    monthlyChart
                }
            } else {
                if !hasAnyLineChartData {
                    Text("표시할 HRV·수면·운동 데이터가 없어요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    lineChart
                    if hasGanttData {
                        ganttChart
                    }
                }
            }

            if let healthKitErrorMessage = viewModel.healthKitErrorMessage {
                Text(healthKitErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            legend
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            legendRow(color: hrvLineColor, symbol: "circle.fill", label: "HRV (애플워치)")
            legendRow(color: sdnnColor, symbol: "triangle.fill", label: "검사 SDNN")
            legendRow(color: sleepColor, symbol: "square.fill", label: "수면")
            legendRow(color: exerciseColor, symbol: "square.fill", label: "운동")
        }
        .padding(.top, 4)
    }

    private func legendRow(color: Color, symbol: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 직접 구현한 드래그 스크롤
    // Swift Charts 내장 chartScrollableAxes가 이 환경에서 잘 반응하지 않아,
    // 드래그 위치를 직접 계산해서 hrvScrollPosition(보이는 구간의 시작 시각)을 갱신함.
    // HRV 차트/간트 차트가 같은 hrvScrollPosition을 공유해서 같이 움직임.
    private func dragToScrollOverlay(proxy: ChartProxy, visibleDomain: TimeInterval) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragAnchorPosition == nil {
                                dragAnchorPosition = hrvScrollPosition
                            }
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotWidth = geo[plotFrame].width
                            guard plotWidth > 0, let anchor = dragAnchorPosition else { return }
                            let timePerPixel = visibleDomain / Double(plotWidth)
                            let deltaSeconds = -Double(value.translation.width) * timePerPixel
                            let proposed = anchor.addingTimeInterval(deltaSeconds)
                            let maxStart = Date().addingTimeInterval(-visibleDomain)
                            hrvScrollPosition = min(proposed, maxStart)
                        }
                        .onEnded { _ in
                            dragAnchorPosition = nil
                        }
                )
        }
    }

    // 라인 차트와 간트 차트가 같은 hrvScrollPosition/visibleDomain을 쓰더라도, 각자 알아서
    // "automatic" 눈금을 고르면 서로 다른 위치에 눈금이 생길 수 있어 명시적으로 동일한 눈금 배열을 계산해서 공유함.
    private var xAxisTickDates: [Date] {
        let strideSeconds: TimeInterval
        switch chartMode {
        case .hourly: strideSeconds = 4 * 60 * 60
        case .daily: strideSeconds = 3 * 24 * 60 * 60
        case .monthly: strideSeconds = 7 * 24 * 60 * 60
        }

        let end = hrvScrollPosition.addingTimeInterval(chartMode.visibleDomain)
        var dates: [Date] = []
        var current = hrvScrollPosition
        while current <= end {
            dates.append(current)
            current = current.addingTimeInterval(strideSeconds)
        }
        return dates
    }

    private func xAxisLabel(for date: Date) -> some View {
        Group {
            switch chartMode {
            case .hourly:
                if Calendar.current.component(.hour, from: date) == 0 {
                    Text(Self.monthDayFormatter.string(from: date)).bold()
                } else {
                    Text(Self.hourMinuteFormatter.string(from: date))
                }
            case .daily, .monthly:
                Text(Self.monthDayFormatter.string(from: date))
            }
        }
        .font(.system(size: 9))
    }

    @AxisContentBuilder
    private var sharedXAxisMarks: some AxisContent {
        AxisMarks(values: xAxisTickDates) { value in
            if let date = value.as(Date.self) {
                AxisValueLabel { xAxisLabel(for: date) }
                AxisGridLine()
                    .foregroundStyle(.gray.opacity(0.25))
                AxisTick()
                    .foregroundStyle(.gray.opacity(0.85))
            }
        }
    }

    private var lineChart: some View {
        baseLineChart.chartXAxis { sharedXAxisMarks }
    }

    private var baseLineChart: some View {
        let range = cachedRange
        let showPointMarkers = currentHRVPoints.count <= 300
        let visibleDomain = chartMode.visibleDomain
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)

        return Chart {
            ForEach(currentHRVPoints) { point in
                LineMark(
                    x: .value("시간", point.date),
                    y: .value("HRV", point.value),
                    series: .value("구간", point.segment)
                )
                .foregroundStyle(hrvLineColor)

                if showPointMarkers {
                    PointMark(
                        x: .value("시간", point.date),
                        y: .value("HRV", point.value)
                    )
                    .symbolSize(40)
                    .foregroundStyle(hrvLineColor)

                    PointMark(
                        x: .value("시간", point.date),
                        y: .value("HRV", point.value)
                    )
                    .symbolSize(16)
                    .foregroundStyle(.white)
                }
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
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartYAxis {
            AxisMarks(values: .stride(by: 50)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
        .chartOverlay { proxy in
            dragToScrollOverlay(proxy: proxy, visibleDomain: visibleDomain)
        }
    }

    private var ganttChart: some View {
        let visibleDomain = chartMode.visibleDomain

        return Chart {
            ForEach(viewModel.sleepRanges) { interval in
                RectangleMark(
                    xStart: .value("수면 시작", interval.start),
                    xEnd: .value("수면 끝", interval.end),
                    yStart: .value("아래", 0),
                    yEnd: .value("위", 1)
                )
                .foregroundStyle(sleepColor.opacity(0.7))
            }

            ForEach(viewModel.exerciseRanges) { interval in
                RectangleMark(
                    xStart: .value("운동 시작", interval.start),
                    xEnd: .value("운동 끝", interval.end),
                    yStart: .value("아래", 0),
                    yEnd: .value("위", 1)
                )
                .foregroundStyle(exerciseColor.opacity(0.7))
            }
        }
        .frame(height: 36)
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis { sharedXAxisMarks }
        .chartOverlay { proxy in
            dragToScrollOverlay(proxy: proxy, visibleDomain: visibleDomain)
        }
    }

    private var monthlyChart: some View {
        let visibleDomain = chartMode.visibleDomain

        return Chart {
            ForEach(viewModel.wearableHRVMonthlyStats) { stat in
                RectangleMark(
                    x: .value("월", stat.monthStart, unit: .month),
                    yStart: .value("최소", stat.min),
                    yEnd: .value("최대", stat.max),
                    width: .ratio(0.4)
                )
                .foregroundStyle(hrvLineColor.opacity(0.35))
                .cornerRadius(6)

                let halfThickness = max((stat.max - stat.min) * 0.015, 0.5)
                RectangleMark(
                    x: .value("월", stat.monthStart, unit: .month),
                    yStart: .value("중앙값 아래", stat.median - halfThickness),
                    yEnd: .value("중앙값 위", stat.median + halfThickness),
                    width: .ratio(0.4)
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
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 9))
                AxisGridLine()
                AxisTick()
            }
        }
        .chartOverlay { proxy in
            dragToScrollOverlay(proxy: proxy, visibleDomain: visibleDomain)
        }
    }
}

#Preview {
    HRVAnalysisView()
}
