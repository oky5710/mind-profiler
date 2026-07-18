import Charts
import SwiftUI
import UIKit

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

    var iconName: String {
        switch self {
        case .hourly: "clock"
        case .daily: "calendar"
        case .monthly: "calendar.circle"
        }
    }
}

// 범례에 나오는 지표 단위. 범례를 탭하면 hiddenSeries에 넣고 빼서 차트에서 보이기/숨기기를 토글한다.
private enum HRVSeries: String, CaseIterable, Identifiable {
    case hrv, sdnn, sleep, exercise, median, outlier
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hrv: "HRV (애플워치)"
        case .sdnn: "검사 SDNN"
        case .sleep: "수면"
        case .exercise: "운동"
        case .median: "최근 30일 중앙값"
        case .outlier: "이상치 (중앙값의 25% 미만)"
        }
    }

    var symbol: String {
        switch self {
        case .hrv: "circle.fill"
        case .sdnn: "triangle.fill"
        case .sleep: "square.fill"
        case .exercise: "square.fill"
        case .median: "minus"
        case .outlier: "circle.fill"
        }
    }
}

struct HRVAnalysisView: View {
    @State private var viewModel = HRVAnalysisViewModel()
    @State private var chartMode: HRVChartMode = .hourly
    @State private var hrvScrollPosition = Date().addingTimeInterval(-HRVChartMode.hourly.visibleDomain)
    @State private var dragAnchorPosition: Date?
    @State private var hiddenSeries: Set<HRVSeries> = []
    @State private var tooltipPoint: HRVAnalysisViewModel.HRVPoint?

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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
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

    // ui-style.md 규칙: 차트 높이는 전체 화면의 40%. 간트 차트는 그 절반의 70%.
    private var lineChartHeight: CGFloat {
        UIScreen.main.bounds.height * 0.4
    }

    private var ganttChartHeight: CGFloat {
        lineChartHeight / 2 * 0.7
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                hrvChart
                Spacer()
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                // 차트 자체는 자기 드래그 제스처가 우선 처리하므로, 여기는 차트 바깥(빈 영역)을
                // 탭했을 때만 걸린다.
                tooltipPoint = nil
            }
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
            tooltipPoint = nil
            recomputeRange()
        }
        .refreshable {
            await viewModel.reload()
            recomputeRange()
        }
    }

    private func recomputeRange() {
        var values = viewModel.examPoints.map(\.sdnn)
        switch chartMode {
        case .hourly, .daily:
            values += currentHRVPoints.map(\.value)
        case .monthly:
            values += viewModel.wearableHRVMonthlyStats.flatMap { [$0.min, $0.max] }
        }
        cachedRange = values.isEmpty ? (min: 0.0, max: 100.0) : (min: values.min()!, max: values.max()!)
    }

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HRV 추이").font(.headline)
                Spacer()
                Picker("보기 단위", selection: $chartMode) {
                    ForEach(HRVChartMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName)
                            .accessibilityLabel(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.bottom, 20)

            hrvChartBody
        }
    }

    private func tooltipLabel(for point: HRVAnalysisViewModel.HRVPoint) -> some View {
        VStack(spacing: 2) {
            Text(Self.tooltipDateFormatter.string(from: point.date))
                .font(.caption2)
            Text("\(String(format: "%.0f", point.value))ms")
                .font(.callout.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    private var hrvChartBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if (viewModel.isLoading || viewModel.isLoadingHealthKit) && !hasAnyLineChartData {
                HeartLoader(height: lineChartHeight)
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
                    baseLineChart
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
            ForEach(HRVSeries.allCases) { series in
                Button {
                    toggleSeries(series)
                } label: {
                    legendRow(color: seriesColor(series), symbol: series.symbol, label: series.label)
                        .opacity(hiddenSeries.contains(series) ? 0.35 : 1)
                }
                .buttonStyle(.plain)
            }
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

    private func toggleSeries(_ series: HRVSeries) {
        if hiddenSeries.contains(series) {
            hiddenSeries.remove(series)
        } else {
            hiddenSeries.insert(series)
        }
    }

    private func seriesColor(_ series: HRVSeries) -> Color {
        switch series {
        case .hrv: hrvLineColor
        case .sdnn: sdnnColor
        case .sleep: sleepColor
        case .exercise: exerciseColor
        case .median: .gray
        case .outlier: .red
        }
    }

    // y축 라벨이 차트 레이아웃 공간을 차지하지 않고 고정된 위치에 떠 있어야 한다는 규칙(ui-style.md) 때문에,
    // 기본 제공되는 leading y축(라벨 너비만큼 플롯 영역을 줄임) 대신 y축은 숨기고 직접 오버레이로 그린다.
    private func yAxisTicks(upperBound: Double) -> [Double] {
        Array(stride(from: 0.0, through: upperBound, by: 50))
    }

    private func yAxisOverlay(proxy: ChartProxy, tickValues: [Double]) -> some View {
        GeometryReader { geo in
            if let plotFrame = proxy.plotFrame {
                let plotRect = geo[plotFrame]
                ZStack(alignment: .topLeading) {
                    ForEach(tickValues, id: \.self) { value in
                        if let y = proxy.position(forY: value) {
                            Path { path in
                                path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY + y))
                                path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY + y))
                            }
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)

                            Text(String(format: "%.0f", value))
                                .font(.system(size: 9))
                                .tracking(1)
                                .padding(.horizontal, 3)
                                .background(Color(.systemBackground).opacity(0.85))
                                .position(x: plotRect.minX + 16, y: plotRect.minY + y)
                        }
                    }
                }
            }
        }
    }

    private func chartOverlay(
        proxy: ChartProxy,
        visibleDomain: TimeInterval,
        yAxisTickValues: [Double],
        xAxisTickDates: [Date],
        xAxisLabel: @escaping (Date) -> AnyView,
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = []
    ) -> some View {
        ZStack {
            xAxisOverlay(proxy: proxy, tickDates: xAxisTickDates, label: xAxisLabel)
            yAxisOverlay(proxy: proxy, tickValues: yAxisTickValues)
            dragToScrollOverlay(proxy: proxy, visibleDomain: visibleDomain, tooltipPoints: tooltipPoints)
        }
    }

    // MARK: - 직접 구현한 드래그 스크롤
    // Swift Charts 내장 chartScrollableAxes가 이 환경에서 잘 반응하지 않아,
    // 드래그 위치를 직접 계산해서 hrvScrollPosition(보이는 구간의 시작 시각)을 갱신함.
    // HRV 차트/간트 차트가 같은 hrvScrollPosition을 공유해서 같이 움직임.
    // tooltipPoints가 있으면 같은 드래그로 가장 가까운 데이터 포인트의 값도 함께 보여준다.
    private func dragToScrollOverlay(
        proxy: ChartProxy,
        visibleDomain: TimeInterval,
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = []
    ) -> some View {
        // 툴팁 말풍선이 화면/차트 밖으로 나가지 않도록, 세로선 자체는 실제 위치에 그리되
        // 말풍선의 x 위치만 플롯 안쪽으로 밀어 넣는다 (말풍선 예상 반너비만큼 여유를 둠).
        let estimatedTooltipHalfWidth: CGFloat = 45

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if !tooltipPoints.isEmpty,
                   let point = tooltipPoint,
                   let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: point.date) {
                    let plotRect = geo[plotFrame]
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX + x, y: plotRect.minY))
                        path.addLine(to: CGPoint(x: plotRect.minX + x, y: plotRect.maxY))
                    }
                    .stroke(Color.primary.opacity(0.5), lineWidth: 1)

                    let clampedLocalX = min(
                        max(x, estimatedTooltipHalfWidth),
                        max(plotRect.width - estimatedTooltipHalfWidth, estimatedTooltipHalfWidth)
                    )
                    tooltipLabel(for: point)
                        .position(x: plotRect.minX + clampedLocalX, y: plotRect.minY + 24)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        // minimumDistance: 0 — 손가락을 움직이지 않는 단순 탭에서도 onChanged가 즉시 발생해야
                        // 툴팁/세로선이 뜬다. 스크롤 자체는 변화량(translation)이 거의 0이라 실질적 이동은 없음.
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragAnchorPosition == nil {
                                    dragAnchorPosition = hrvScrollPosition
                                }
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotRect = geo[plotFrame]
                                let plotWidth = plotRect.width
                                guard plotWidth > 0, let anchor = dragAnchorPosition else { return }
                                let timePerPixel = visibleDomain / Double(plotWidth)
                                let deltaSeconds = -Double(value.translation.width) * timePerPixel
                                let proposed = anchor.addingTimeInterval(deltaSeconds)
                                let maxStart = Date().addingTimeInterval(-visibleDomain)
                                hrvScrollPosition = min(proposed, maxStart)

                                if !tooltipPoints.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipPoint = tooltipPoints.min {
                                            abs($0.date.timeIntervalSince(touchedDate)) < abs($1.date.timeIntervalSince(touchedDate))
                                        }
                                    }
                                }
                            }
                            .onEnded { _ in
                                dragAnchorPosition = nil
                                // 툴팁은 손을 떼도 유지 — 다른 위치를 다시 탭하기 전까지는 사라지지 않는다.
                            }
                    )
            }
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
        .tracking(1)
    }

    // 월별 모드는 한 달 단위 막대라서 다른 모드의 촘촘한 시간 눈금 대신, 30일 이상 간격은
    // "M월"만 표기하는 규칙(ui-style.md 날짜 표기 규칙)에 맞춰 달마다 하나씩 눈금을 찍는다.
    private var monthlyTickDates: [Date] {
        let calendar = Calendar.current
        let end = hrvScrollPosition.addingTimeInterval(chartMode.visibleDomain)
        var dates: [Date] = []
        var current = calendar.dateInterval(of: .month, for: hrvScrollPosition)?.start ?? hrvScrollPosition
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private func monthlyAxisLabel(for date: Date) -> some View {
        Text(Self.monthFormatter.string(from: date))
            .bold()
            .font(.system(size: 9))
            .tracking(1)
    }

    // x축 라벨도 y축과 같은 이유(ui-style.md)로 레이아웃 공간을 차지하지 않고 차트 안에 고정 위치로 띄운다.
    private func xAxisOverlay(proxy: ChartProxy, tickDates: [Date], label: @escaping (Date) -> AnyView) -> some View {
        GeometryReader { geo in
            if let plotFrame = proxy.plotFrame {
                let plotRect = geo[plotFrame]

                // 라벨 간격이 10px 이하로 겹칠 것 같으면 뒤쪽 라벨은 생략한다 (그리드 선은 계속 그림).
                var lastLabelX: CGFloat?
                let visibleLabelDates: Set<Date> = Set(tickDates.compactMap { date -> Date? in
                    guard let x = proxy.position(forX: date) else { return nil }
                    if let last = lastLabelX, x - last < 10 { return nil }
                    lastLabelX = x
                    return date
                })

                ZStack(alignment: .topLeading) {
                    // 차트 하단을 가로지르는 x축 기준선 (틱마다 그리는 세로 그리드와는 별개).
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                        path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
                    }
                    .stroke(Color(white: 0.35), lineWidth: 1)

                    ForEach(tickDates, id: \.self) { date in
                        if let x = proxy.position(forX: date) {
                            Path { path in
                                path.move(to: CGPoint(x: plotRect.minX + x, y: plotRect.minY))
                                path.addLine(to: CGPoint(x: plotRect.minX + x, y: plotRect.maxY))
                            }
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)

                            if visibleLabelDates.contains(date) {
                                label(date)
                                    .padding(.horizontal, 3)
                                    .background(Color(.systemBackground).opacity(0.85))
                                    .position(x: plotRect.minX + x, y: plotRect.maxY - 10)
                            }
                        }
                    }
                }
            }
        }
    }

    private var baseLineChart: some View {
        let range = cachedRange
        let visibleDomain = chartMode.visibleDomain
        let visibleStart = hrvScrollPosition
        let visibleEnd = hrvScrollPosition.addingTimeInterval(visibleDomain)
        // currentHRVPoints는 HealthKit에서 가져온 전체 기간 데이터라, 그 개수로 판단하면 시간별 모드에서
        // 실제로 보이는 건 하루치뿐이어도 과거 데이터가 많으면 점이 영영 안 뜨게 된다 — 보이는 구간만 센다.
        let showPointMarkers = currentHRVPoints.filter { $0.date >= visibleStart && $0.date <= visibleEnd }.count <= 300
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)
        let outlierThreshold = viewModel.recentThirtyDayMedian.map { $0 * 0.25 }
        let showOutliers = !hiddenSeries.contains(.outlier)

        return Chart {
            if !hiddenSeries.contains(.hrv) {
                ForEach(currentHRVPoints) { point in
                    let isOutlier = showOutliers && (outlierThreshold.map { point.value < $0 } ?? false)

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
                        .symbolSize(80)
                        .foregroundStyle(isOutlier ? .red : hrvLineColor)

                        PointMark(
                            x: .value("시간", point.date),
                            y: .value("HRV", point.value)
                        )
                        .symbolSize(32)
                        .foregroundStyle(.white)
                    }
                }
            }

            if !hiddenSeries.contains(.median), let median = viewModel.recentThirtyDayMedian {
                RuleMark(y: .value("최근 30일 중앙값", median))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if !hiddenSeries.contains(.sdnn) {
                ForEach(viewModel.examPoints) { point in
                    PointMark(
                        x: .value("검사일", point.date),
                        y: .value("SDNN", point.sdnn)
                    )
                    .symbol(.triangle)
                    .foregroundStyle(sdnnColor)
                }
            }
        }
        .frame(height: lineChartHeight)
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: yAxisTicks(upperBound: yAxisUpperBound),
                xAxisTickDates: xAxisTickDates,
                xAxisLabel: { date in AnyView(xAxisLabel(for: date)) },
                tooltipPoints: currentHRVPoints
            )
        }
    }

    private static let shortSleepThreshold: TimeInterval = 5 * 60 * 60

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        return "\(totalMinutes / 60)시간 \(totalMinutes % 60)분"
    }

    private var ganttChart: some View {
        let visibleDomain = chartMode.visibleDomain

        return Chart {
            if !hiddenSeries.contains(.sleep) {
                ForEach(viewModel.sleepRanges) { interval in
                    let duration = interval.end.timeIntervalSince(interval.start)
                    let isShort = duration < Self.shortSleepThreshold

                    RectangleMark(
                        xStart: .value("수면 시작", interval.start),
                        xEnd: .value("수면 끝", interval.end),
                        yStart: .value("아래", 0),
                        yEnd: .value("위", 1)
                    )
                    .foregroundStyle((isShort ? Color.red : sleepColor).opacity(0.7))
                    .annotation(position: .overlay) {
                        if isShort {
                            Text(formattedDuration(duration))
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            if !hiddenSeries.contains(.exercise) {
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
        }
        .frame(height: ganttChartHeight)
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: [],
                xAxisTickDates: xAxisTickDates,
                xAxisLabel: { date in AnyView(xAxisLabel(for: date)) }
            )
        }
    }

    private var monthlyChart: some View {
        let range = cachedRange
        let visibleDomain = chartMode.visibleDomain
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)

        return Chart {
            if !hiddenSeries.contains(.hrv) {
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
            }

            if !hiddenSeries.contains(.sdnn) {
                ForEach(viewModel.examPoints) { point in
                    PointMark(
                        x: .value("검사일", point.date),
                        y: .value("SDNN", point.sdnn)
                    )
                    .symbol(.triangle)
                    .foregroundStyle(sdnnColor)
                }
            }
        }
        .frame(height: lineChartHeight)
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: yAxisTicks(upperBound: yAxisUpperBound),
                xAxisTickDates: monthlyTickDates,
                xAxisLabel: { date in AnyView(monthlyAxisLabel(for: date)) }
            )
        }
    }
}

#Preview {
    HRVAnalysisView()
}
