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
        // 캘린더/수면 툴팁은 간트 차트 자체(세로 폭이 좁음)가 아니라 라인+간트를 합친 이 스택 전체를
        // 덮는 오버레이에서 그린다 — 세로 공간이 훨씬 넉넉해서 내용이 길어도 잘리지 않는다. x 좌표는
        // 간트 차트의 드래그 핸들러(HRVAnalysisView+Axes.swift)가 계산해서 넘겨준다. 간트 차트 자체를
        // 가리면 안 되니 그 아래쪽 여백에 띄운다(대략적인 툴팁 절반 높이만큼 더 내려서 여유를 둠).
        .overlay(alignment: .topLeading) {
            let tooltipY = lineChartHeight + 8 + ganttChartHeight + 50
            ZStack(alignment: .topLeading) {
                if let x = calendarTooltipAnchorX, let event = tooltipCalendarEvent {
                    tooltipLabel(for: event)
                        .position(x: x, y: tooltipY)
                }
                if let x = sleepTooltipAnchorX, let sleepRange = tooltipSleepRange {
                    tooltipLabel(for: sleepRange)
                        .position(x: x, y: tooltipY)
                }
            }
            .allowsHitTesting(false)
        }
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

    private static var shortSleepThreshold: TimeInterval { 5 * 60 * 60 }

    func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        return "\(totalMinutes / 60)시간 \(totalMinutes % 60)분"
    }

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

    var monthlyChart: some View {
        let range = cachedRange
        let visibleDomain = chartMode.visibleDomain
        let yAxisUpperBound = max(ceil(range.max / 50) * 50, 50)

        return Chart {
            ForEach(viewModel.wearableRMSSDMonthlyStats) { stat in
                RectangleMark(
                    x: .value("월", stat.monthStart, unit: .month),
                    yStart: .value("최소", stat.min),
                    yEnd: .value("최대", stat.max),
                    width: .fixed(monthlyBarWidth)
                )
                .foregroundStyle(rmssdColor.opacity(0.35))
                .cornerRadius(6)

                // 두께를 그 달 자체의 최소~최대 범위로 계산하면 달마다 변동폭이 달라서 두께가
                // 들쭉날쭉해진다 — 전체 y축 범위 기준으로 고정해서 모든 달이 같은 두께가 되게 한다.
                let halfThickness = max(yAxisUpperBound * 0.01, 0.5)
                RectangleMark(
                    x: .value("월", stat.monthStart, unit: .month),
                    yStart: .value("중앙값 아래", stat.median - halfThickness),
                    yEnd: .value("중앙값 위", stat.median + halfThickness),
                    width: .fixed(monthlyBarWidth)
                )
                .foregroundStyle(rmssdColor)
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
        .background {
            // 막대 너비 = bandwidth(달 하나가 차지하는 폭)의 50%, 10~30px로 clamp.
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

    private func updateMonthlyBarWidth(plotWidth: CGFloat) {
        let bandCount = max(monthlyTickDates.count, 1)
        let bandwidth = plotWidth / CGFloat(bandCount)
        monthlyBarWidth = min(max(bandwidth * 0.5, 10), 30)
    }
}
