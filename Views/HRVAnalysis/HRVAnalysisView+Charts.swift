import Charts
import SwiftUI

// 실제 차트 정의 (라인+Gantt / 월별). 축/스크롤/툴팁 오버레이는 HRVAnalysisView+Axes.swift 참고.
extension HRVAnalysisView {
    // baseLineChart/ganttChart는 각자 별도의 Chart라 세로 그리드도 각자 자기 plotRect 안에서만 그려진다.
    // 그 결과 두 차트 사이 간격(레이아웃상 유지하고 싶은 여백) 부분에서 그리드 선이 끊겨 보이므로,
    // 그 간격만큼을 이어주는 짧은 선을 배경에 덧그려서 세로 그리드가 끊기지 않고 이어진 것처럼 보이게 한다.
    // Gantt 차트는 데이터 유무와 상관없이 항상 그린다 (x축은 라인 차트와 동일) — 그래야 수면/운동
    // 데이터가 로딩 중간에 들어와도 차트 높이가 갑자기 늘어나면서 아래 범례가 밀려 내려가지 않는다.
    var lineAndGanttChartsStack: some View {
        VStack(spacing: 8) {
            baseLineChart
            ganttChart
        }
        .background(alignment: .topLeading) {
            GeometryReader { geo in
                ForEach(xAxisTickDates, id: \.self) { date in
                    let fraction = date.timeIntervalSince(hrvScrollPosition) / chartMode.visibleDomain
                    let x = geo.size.width * fraction
                    Path { path in
                        path.move(to: CGPoint(x: x, y: lineChartHeight))
                        path.addLine(to: CGPoint(x: x, y: lineChartHeight + 8))
                    }
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                }
            }
        }
        // 상세 패널은 오버레이라 이 스택의 레이아웃 높이에 영향을 주지 않는다 — x축 위치(간트 차트
        // 바로 아래)에 붙여서 그 아래 범례 위에 겹쳐 보이게 한다. 히트 테스트는 켜둔 채로 둔다 —
        // 패널이 자기 영역의 탭을 그대로 흡수해야 뒤에 가려진 범례 버튼이 같이 눌리지 않는다.
        .overlay(alignment: .top) {
            selectedItemDetailPanel
                .offset(y: lineChartHeight + 8 + ganttChartHeight)
        }
        // 겹치는 범례가 선언 순서상 나중에 그려져 패널을 가리므로, zIndex로 항상 위에 오도록 고정한다.
        .zIndex(1)
    }

    var baseLineChart: some View {
        let range = cachedRange
        let visibleDomain = chartMode.visibleDomain
        let visibleStart = hrvScrollPosition
        let visibleEnd = hrvScrollPosition.addingTimeInterval(visibleDomain)
        // currentRMSSDPoints는 HealthKit에서 가져온 전체 기간 데이터라, 그 개수로 판단하면 시간별 모드에서
        // 실제로 보이는 건 하루치뿐이어도 과거 데이터가 많으면 점이 영영 안 뜨게 된다 — 보이는 구간만 센다.
        let showRMSSDPointMarkers = currentRMSSDPoints.filter { $0.date >= visibleStart && $0.date <= visibleEnd }.count <= 300
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)

        return Chart {
            // SDNN은 rMSSD와의 값 차이를 참고만 하려는 용도라, 시간별 모드에서만 눈에 덜 띄게
            // 시스템 회색(systemGray4)으로 뒤쪽에 깔아서 그린다 — rMSSD 라인이 항상 위에 보인다.
            // 두께를 rMSSD보다 굵게 하면 흐린 색과 별개로 오히려 더 튀어 보여서, 두께는 rMSSD와
            // 동일하게(기본값) 둔다.
            if chartMode == .hourly, !hiddenSeries.contains(.sdnn) {
                ForEach(viewModel.wearableSDNNPointsHourly) { point in
                    LineMark(
                        x: .value("시간", point.date),
                        y: .value("SDNN", point.value),
                        series: .value("구간", "sdnn-\(point.segment)")
                    )
                    .foregroundStyle(Theme.systemGray4)
                }
            }

            if !hiddenSeries.contains(.rmssd) {
                ForEach(currentRMSSDPoints) { point in
                    LineMark(
                        x: .value("시간", point.date),
                        y: .value("rMSSD", point.value),
                        series: .value("구간", "rmssd-\(point.segment)")
                    )
                    .foregroundStyle(rmssdColor)

                    if showRMSSDPointMarkers {
                        PointMark(
                            x: .value("시간", point.date),
                            y: .value("rMSSD", point.value)
                        )
                        .symbolSize(80)
                        .foregroundStyle(rmssdColor)

                        PointMark(
                            x: .value("시간", point.date),
                            y: .value("rMSSD", point.value)
                        )
                        .symbolSize(32)
                        .foregroundStyle(.white)
                    }
                }
            }

            if !hiddenSeries.contains(.examRmssd) {
                ForEach(viewModel.examPoints) { point in
                    PointMark(
                        x: .value("검사일", point.date),
                        y: .value("검사 rMSSD", point.rmssd)
                    )
                    .symbol(.triangle)
                    .foregroundStyle(examRmssdColor)
                }
            }

            if !hiddenSeries.contains(.median), let median = viewModel.recentThirtyDayRMSSDMedian {
                RuleMark(y: .value("최근 30일 중앙값", median))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                tooltipPoints: currentRMSSDPoints
            )
        }
    }

    static var shortSleepThreshold: TimeInterval { 5 * 60 * 60 }

    func allDayEventColor(for category: CalendarEventCategory) -> Color {
        switch category {
        case .holiday: Theme.holiday
        case .vacation: Theme.vacation
        case .general: calendarEventColor
        }
    }

    // 여러 날짜에 걸친 종일 일정(예: 3일짜리 휴가)은 원 하나로 뭉뚱그리지 않고, 걸치는 날마다
    // 자정(날짜가 바뀌는 지점)에 원을 하나씩 찍어서 캘린더 앱처럼 날짜별로 표시한다. 툴팁도 같은
    // event.start(자정) 기준으로 위치를 잡으므로 원과 툴팁이 항상 같은 x 위치에 온다.
    var allDayEventDayMarkers: [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] {
        let calendar = Calendar.current
        return viewModel.calendarEventRanges
            .filter(\.isAllDay)
            .flatMap { event -> [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] in
                let dayCount = max(calendar.dateComponents([.day], from: event.start, to: event.end).day ?? 1, 1)
                return (0..<dayCount).compactMap { offset in
                    calendar.date(byAdding: .day, value: offset, to: event.start).map { (day: $0, event: event) }
                }
            }
    }

    var ganttChart: some View {
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
                    .cornerRadius(4)
                    .annotation(position: .overlay) {
                        if isShort {
                            Text(SleepAnalysisService.formattedDuration(duration))
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
                    .cornerRadius(4)
                }
            }

            // 캘린더 일정은 수면/운동과 한 레인에 겹쳐서 표시하되, 시간이 있는 일정과 종일 일정을
            // 다르게 그린다 — 시간 일정은 전체 높이에 옅게 깐 막대, 종일 일정은 겹치는 막대 위에서도
            // 묻히지 않도록 흰 테두리가 있는 원(날짜당 하나)으로 표시한다.
            if !hiddenSeries.contains(.calendarEvent) {
                ForEach(viewModel.calendarEventRanges.filter { !$0.isAllDay }) { event in
                    RectangleMark(
                        xStart: .value("일정 시작", event.start),
                        xEnd: .value("일정 끝", event.end),
                        yStart: .value("아래", 0),
                        yEnd: .value("위", 1)
                    )
                    .foregroundStyle(calendarEventColor.opacity(0.35))
                    .cornerRadius(4)
                }

                ForEach(Array(allDayEventDayMarkers.enumerated()), id: \.offset) { _, marker in
                    // 흰 원(뒤, 크게) 위에 일정 색 원(앞, 작게)을 겹쳐서 테두리처럼 보이게 한다 —
                    // 뒤에 깔린 막대와 색이 겹쳐도 항상 구분되어 보인다.
                    PointMark(
                        x: .value("날짜", marker.day),
                        y: .value("위치", 0.9)
                    )
                    .symbolSize(90)
                    .foregroundStyle(.white)

                    PointMark(
                        x: .value("날짜", marker.day),
                        y: .value("위치", 0.9)
                    )
                    .symbolSize(60)
                    .foregroundStyle(allDayEventColor(for: marker.event.category))
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
                xAxisLabel: { date in AnyView(xAxisLabel(for: date)) },
                tooltipRanges: hiddenSeries.contains(.calendarEvent) ? [] : viewModel.calendarEventRanges.filter { !$0.isAllDay },
                tooltipSleepRanges: hiddenSeries.contains(.sleep) ? [] : viewModel.sleepRanges,
                tooltipAllDayMarkers: hiddenSeries.contains(.calendarEvent) ? [] : allDayEventDayMarkers
            )
        }
    }

    // 월별 모드는 주식 차트의 캔들스틱처럼 위쪽엔 rMSSD 최소~최대(심지)+1Q~3Q(몸통)+중앙값을,
    // 원래 간트 차트가 있던 아래쪽엔 그 달의 CV(변동계수)를 막대로 보여준다.
    var monthlyChart: some View {
        VStack(spacing: 8) {
            monthlyCandlestickChart
            monthlyCVChart
        }
        .background {
            // 막대 너비 = bandwidth(달 하나가 차지하는 폭)의 50%를 다시 70%로 줄인 값, 10~30px로 clamp.
            // plot 폭은 축을 숨겨서 프레임 전체와 같으므로, 컨테이너 폭을 그대로 plot 폭으로 쓴다.
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateMonthlyBarWidth(plotWidth: geo.size.width) }
                    .onChange(of: geo.size.width) { _, newWidth in
                        updateMonthlyBarWidth(plotWidth: newWidth)
                    }
            }
        }
    }

    private var monthlyCandlestickChart: some View {
        let range = cachedRange
        let visibleDomain = chartMode.visibleDomain
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)

        return Chart {
            if !hiddenSeries.contains(.rmssd) {
                ForEach(viewModel.wearableRMSSDMonthlyStats) { stat in
                    // 주식 차트의 고가-저가 심지처럼, 최소~최대 범위를 얇은 세로선으로 — 박스보다
                    // 먼저 그려서 제일 뒤로 보내고, 박스와 겹치는 부분은 박스 아래 가려지게 한다.
                    RuleMark(
                        x: .value("월", stat.monthStart, unit: .month),
                        yStart: .value("최소", stat.min),
                        yEnd: .value("최대", stat.max)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(rmssdColor.opacity(0.5))

                    // 박스플롯의 몸통처럼, 1Q~3Q 구간을 사각형으로 — 연보라(Theme.rmssdRange)로
                    // 불투명하게 채워서 심지 위에 겹쳐도 박스 구간의 심지가 완전히 가려진다.
                    RectangleMark(
                        x: .value("월", stat.monthStart, unit: .month),
                        yStart: .value("1Q", stat.q1),
                        yEnd: .value("3Q", stat.q3),
                        width: .fixed(monthlyBarWidth)
                    )
                    .foregroundStyle(Theme.rmssdRange)
                    .cornerRadius(4)

                    // 중앙값 선은 값(y축) 범위가 아니라 고정 픽셀 두께(2px)로 그려서, y축 스케일과
                    // 무관하게 항상 같은 굵기로 보이고 다른 두 마크보다 위(제일 앞)에 그려진다.
                    RectangleMark(
                        x: .value("월", stat.monthStart, unit: .month),
                        y: .value("중앙값", stat.median),
                        width: .fixed(monthlyBarWidth),
                        height: .fixed(2)
                    )
                    .foregroundStyle(rmssdColor)
                }
            }

            if !hiddenSeries.contains(.examRmssd) {
                ForEach(viewModel.examPoints) { point in
                    PointMark(
                        x: .value("검사일", point.date),
                        y: .value("검사 rMSSD", point.rmssd)
                    )
                    .symbol(.triangle)
                    .foregroundStyle(examRmssdColor)
                }
            }

            if !hiddenSeries.contains(.median), let median = viewModel.recentThirtyDayRMSSDMedian {
                RuleMark(y: .value("최근 30일 중앙값", median))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
                xAxisLabel: { date in AnyView(monthlyAxisLabel(for: date)) },
                xAxisLabelPositionDate: monthMidpoint
            )
        }
    }

    private var monthlyCVChart: some View {
        let visibleDomain = chartMode.visibleDomain
        let maxCV = viewModel.wearableRMSSDMonthlyStats.compactMap(\.cv).max() ?? 0
        // 막대 위에 값(annotation)을 적을 여백이 필요해서, 최댓값보다 넉넉하게 위쪽 여유를 둔다.
        let yAxisUpperBound = max(ceil(maxCV * 1.35 / 10) * 10, 10)

        return Chart {
            if !hiddenSeries.contains(.cv) {
                ForEach(viewModel.wearableRMSSDMonthlyStats) { stat in
                    if let cv = stat.cv {
                        BarMark(
                            x: .value("월", stat.monthStart, unit: .month),
                            y: .value("CV", cv),
                            width: .fixed(monthlyBarWidth)
                        )
                        .foregroundStyle(Theme.systemTeal)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            Text("\(String(format: "%.1f", cv))%")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: ganttChartHeight)
        .chartXScale(domain: hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain))
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: [],
                xAxisTickDates: monthlyTickDates,
                xAxisLabel: { _ in AnyView(EmptyView()) }
            )
        }
    }

    private func updateMonthlyBarWidth(plotWidth: CGFloat) {
        let bandCount = max(monthlyTickDates.count, 1)
        let bandwidth = plotWidth / CGFloat(bandCount)
        monthlyBarWidth = min(max(bandwidth * 0.5, 10), 30) * 0.7
    }
}
