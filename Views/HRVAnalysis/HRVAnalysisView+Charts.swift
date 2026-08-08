import Charts
import SwiftUI

// 일별 모드의 안정시 심박수·수면시간·일광시간 막대 차트가 공통으로 필요로 하는 x축 값.
// 이 프로토콜을 채택하는 타입(HRVPoint 등)이 이미 @MainActor격리된 HRVAnalysisViewModel에
// 중첩돼 있어 Identifiable 준수 자체가 MainActor에 격리돼 있다 — 이 프로토콜도 맞춰야 한다.
@MainActor
protocol DatedPoint: Identifiable {
    var date: Date { get }
}

// 실제 차트 정의 (라인+Gantt / 월별). 축/스크롤/툴팁 오버레이는 HRVAnalysisView+Axes.swift 참고.
extension HRVAnalysisView {
    // 일별 모드의 안정시 심박수·수면시간·일광시간 막대 차트는 값 필드·색·y축 범위만 다르고 나머지
    // 뼈대(막대 폭, "현재" 기준선, 높이, 오버레이 구성)가 동일해서 하나로 합쳤다.
    // showsTopDivider: 이 차트 바로 위가 다른 막대 차트(구분선이 필요)인지, 라인 차트(이미 그
    // 자체로 경계가 보여서 필요 없음)인지에 따라 다르다 — 안정시 심박수 차트만 false.
    // isBottomChart: 일별 스택 전체의 x축 라벨은 맨 아래 차트에서만 보여준다.
    func dailyBarChart<Point: DatedPoint>(
        points: [Point],
        value: @escaping (Point) -> Double,
        valueLabel: String,
        isHidden: Bool,
        color: Color,
        yAxisUpperBound: Double,
        yAxisTicks: [Double],
        showsTopDivider: Bool,
        isBottomChart: Bool
    ) -> some View {
        Chart {
            if !isHidden {
                ForEach(points) { point in
                    BarMark(
                        x: .value("날짜", point.date),
                        y: .value(valueLabel, value(point)),
                        width: .fixed(8)
                    )
                    .foregroundStyle(color.opacity(0.7))
                    .cornerRadius(4)
                }
            }

            if visibleDateRange.contains(Date()) {
                RuleMark(x: .value("현재", Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .frame(height: ganttChartHeight * 0.65)
        .chartXScale(domain: visibleDateRange)
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .overlay(alignment: .top) {
            if showsTopDivider {
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(height: 1)
            }
        }
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: yAxisTicks,
                xAxisTickDates: xAxisTickDates,
                xAxisLabel: { date in AnyView(xAxisLabel(for: date)) },
                xAxisLabelBelow: isBottomChart,
                showsXAxisLabels: isBottomChart,
                showsXAxisBaseline: isBottomChart,
                showsYAxisGridLines: false,
                showsPointTooltip: false,
                tooltipPoints: currentRMSSDPoints
            )
        }
    }
    // baseLineChart/ganttChart 사이 간격을 아예 없앴다 — 간격이 있으면 라인차트의 x축 기준선과
    // 간트 차트의 x축 기준선 사이에서 간트 막대를 정중앙에 두는 계산이 그 간격만큼 더 복잡해지고,
    // 시각적으로도 위아래 여백을 맞추기 더 어려워진다. 간격이 없으면 간트 차트 안에서만 위아래
    // 대칭으로 여백을 주면 그대로 두 기준선 사이 정중앙이 된다.
    // Gantt 차트는 데이터 유무와 상관없이 항상 그린다 (x축은 라인 차트와 동일) — 그래야 수면/운동
    // 데이터가 로딩 중간에 들어와도 차트 높이가 갑자기 늘어나면서 아래 범례가 밀려 내려가지 않는다.
    var lineAndGanttChartsStack: some View {
        VStack(spacing: 0) {
            baseLineChart
            // 일별 모드는 간트 차트(수면/운동/캘린더) 대신 안정시 심박수 막대 차트를 보여준다 —
            // 일별로 뭉친 하루 대표값 시점에서는 시/분 단위 구간 막대가 더 이상 의미가 없어서다.
            // 시간별 모드는 기존 간트 차트를 2/3 높이로 줄이고, 그 아래 커피/약복용/이벤트
            // 아이콘 레인(1/3 높이)을 새로 추가한다.
            if chartMode == .daily {
                restingHeartRateChart
                nightlySleepChart
                daylightChart
            } else {
                ganttChart
                hourlyMarkerLane
            }
        }
        .id(chartMode)
        // 상세 패널은 오버레이라 이 스택의 레이아웃 높이에 영향을 주지 않는다 — x축 위치(간트 차트
        // 바로 아래)에 붙여서 그 아래 범례 위에 겹쳐 보이게 한다. 히트 테스트는 켜둔 채로 둔다 —
        // 패널이 자기 영역의 탭을 그대로 흡수해야 뒤에 가려진 범례 버튼이 같이 눌리지 않는다.
        .overlay(alignment: .top) {
            selectedItemDetailPanel
                .offset(y: lineChartHeight + ganttChartHeight)
        }
        // 겹치는 범례가 선언 순서상 나중에 그려져 패널을 가리므로, zIndex로 항상 위에 오도록 고정한다.
        .zIndex(1)
        // 라인 차트와 간트 차트를 합친 전체 영역에 딱 한 번만 붙여서, 핀치의 두 손가락이 서로 다른
        // 차트 위에 떨어져도 하나의 핀치로 인식되게 한다 (HRVAnalysisView+Axes.swift 참고).
        .contentShape(Rectangle())
        .simultaneousGesture(magnifyToZoomGesture)
    }

    var baseLineChart: some View {
        let range = cachedRange
        let visibleStart = hrvScrollPosition
        let visibleEnd = hrvScrollPosition.addingTimeInterval(visibleDomain)
        let showRMSSDPointMarkers = currentRMSSDPoints.count <= 300
        let yAxisUpperBound = min(
            max(ceil(range.max / 50) * 50, 50),
            Self.maximumRMSSDChartValue
        )
        let recentMedianSegments = viewModel.recentMedianSegments(start: visibleStart, end: visibleEnd)

        return Chart {
            // SDNN은 rMSSD와의 값 차이를 참고만 하려는 용도라, 시간별 모드에서만 눈에 덜 띄게
            // 시스템 회색(systemGray4)으로 뒤쪽에 깔아서 그린다 — rMSSD 라인이 항상 위에 보인다.
            // 두께를 rMSSD보다 굵게 하면 흐린 색과 별개로 오히려 더 튀어 보여서, 두께는 rMSSD와
            // 동일하게(기본값) 둔다.
            if chartMode == .hourly, !hiddenSeries.contains(.sdnn) {
                ForEach(visibleSDNNPoints) { point in
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
                    // 선 자체는 브랜드 색(primary)으로 통일하고, rmssdColor(iris)는 그 위에 찍히는
                    // 포인트(정상/저하/상승 등 의미가 있는 색 구분)에만 남겨서 선과 점의 역할을
                    // 시각적으로 분리한다.
                    LineMark(
                        x: .value("시간", point.date),
                        y: .value("rMSSD", point.value),
                        series: .value("구간", "rmssd-\(point.segment)")
                    )
                    .foregroundStyle(Theme.primary)

                    if showRMSSDPointMarkers {
                        // 실제로 알림에 응답해 기분까지 기록한 포인트(RMSSDEventEntry)는 원 테두리
                        // 대신 꽉 찬 다이아몬드로 — 낮음이면 빨강. 응답하지 않은 낮음/높음 포인트는
                        // 기존처럼 테두리(바깥쪽 링)만 그 색으로 바꿔서 표시한다.
                        let matchedEvent = matchedRMSSDEvent(for: point.date)
                        if let event = matchedEvent, event.direction == RMSSDThresholdDirection.high.rawValue {
                            // 높음(150%+) 로그는 다이아몬드 대신 원으로 — 같은 색의 옅은(10%) 테두리를
                            // 살짝 더 큰 원을 뒤에 겹쳐 그려서 흉내 낸다(PointMark는 실제 stroke를
                            // 지원하지 않는다).
                            PointMark(
                                x: .value("시간", point.date),
                                y: .value("rMSSD", point.value)
                            )
                            .symbolSize(110)
                            .foregroundStyle(Theme.rmssdHigh.opacity(0.1))

                            PointMark(
                                x: .value("시간", point.date),
                                y: .value("rMSSD", point.value)
                            )
                            .symbolSize(90)
                            .foregroundStyle(Theme.rmssdHigh)
                        } else if matchedEvent != nil {
                            // 여기 도달했다는 건 위에서 높음(high)이 아니라고 걸러졌다는 뜻이라 낮음뿐이다.
                            PointMark(
                                x: .value("시간", point.date),
                                y: .value("rMSSD", point.value)
                            )
                            .symbol(.diamond)
                            .symbolSize(90)
                            .foregroundStyle(.red)
                        } else {
                            // 최근 30일 중앙값의 50% 미만/150% 이상으로 급격히 변한 값은 눈에 띄게
                            // 원 테두리를 빨강/초록으로 — 백그라운드 급격한 변화 알림(RMSSDThreshold)과
                            // 같은 기준을 쓴다.
                            let direction = viewModel.recentPeriodMedian(at: point.date).flatMap {
                                RMSSDThreshold.direction(value: point.value, median: $0)
                            }
                            let ringColor: Color = switch direction {
                            case .low: .red
                            case .high: Theme.rmssdHigh
                            case nil: rmssdColor
                            }

                            PointMark(
                                x: .value("시간", point.date),
                                y: .value("rMSSD", point.value)
                            )
                            .symbolSize(80)
                            .foregroundStyle(ringColor)

                            PointMark(
                                x: .value("시간", point.date),
                                y: .value("rMSSD", point.value)
                            )
                            .symbolSize(32)
                            .foregroundStyle(.white)
                        }
                    }
                }
            }

            if !hiddenSeries.contains(.examRmssd) {
                ForEach(visibleExamPoints) { point in
                    PointMark(
                        x: .value("검사일", point.date),
                        y: .value("검사 rMSSD", point.rmssd)
                    )
                    .symbol(.triangle)
                    .foregroundStyle(examRmssdColor)
                }
            }

            if chartMode == .hourly, !hiddenSeries.contains(.median) {
                ForEach(Array(recentMedianSegments.enumerated()), id: \.offset) { index, segment in
                    RuleMark(
                        xStart: .value("기준 시작", segment.start),
                        xEnd: .value("기준 끝", segment.end),
                        y: .value("최근 30일 시간대별 중앙값", segment.value)
                    )
                    .foregroundStyle(sleepColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    if index > 0 {
                        RuleMark(
                            x: .value("기준 변경", segment.start),
                            yStart: .value("이전 중앙값", recentMedianSegments[index - 1].value),
                            yEnd: .value("현재 중앙값", segment.value)
                        )
                        .foregroundStyle(sleepColor)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }

            if visibleDateRange.contains(Date()) {
                RuleMark(x: .value("현재", Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .frame(height: lineChartHeight)
        .chartXScale(domain: visibleDateRange)
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartPlotStyle { $0.clipped() }
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

    // baseLineChart와 ganttChart 사이 간격이 없으므로(spacing: 0), 간트 차트 안에서 위아래
    // 대칭으로 10pt만 남기면 그대로 "위에 있는 x축 라인"(라인차트 축)과 "아래에 있는 x축 라인"
    // (간트 자신의 축) 사이 정중앙이 된다.
    private static let ganttBarMarginPoints: CGFloat = 4

    var ganttBarYStart: Double {
        guard ganttBarsHeight > 0 else { return 0 }
        return Double(Self.ganttBarMarginPoints / ganttBarsHeight)
    }

    var ganttBarYEnd: Double { 1 - ganttBarYStart }

    func allDayEventColor(for category: CalendarEventCategory) -> Color {
        switch category {
        case .holiday: Theme.holiday
        case .vacation: Theme.vacation
        case .general: calendarEventColor
        }
    }

    func dailyMarkerColor(for kind: HRVAnalysisViewModel.DailyMarkerKind) -> Color {
        switch kind {
        case .coffee: Theme.hourlyCoffeeMarker
        case .medication: Theme.hourlyMedicationMarker
        case .symptom: Theme.systemRed
        case .event: calendarEventColor
        }
    }

    // 여러 날짜에 걸친 종일 일정(예: 3일짜리 휴가)은 원 하나로 뭉뚱그리지 않고, 걸치는 날마다
    // 자정(날짜가 바뀌는 지점)에 원을 하나씩 찍어서 캘린더 앱처럼 날짜별로 표시한다. 툴팁도 같은
    // event.start(자정) 기준으로 위치를 잡으므로 원과 툴팁이 항상 같은 x 위치에 온다.
    var allDayEventDayMarkers: [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] {
        let calendar = Calendar.current
        return viewModel.calendarEventRanges
            .filter { $0.isAllDay && $0.start < visibleEnd && $0.end > visibleStart }
            .flatMap { event -> [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] in
                let dayCount = max(calendar.dateComponents([.day], from: event.start, to: event.end).day ?? 1, 1)
                return (0..<dayCount).compactMap { offset in
                    calendar.date(byAdding: .day, value: offset, to: event.start).map { (day: $0, event: event) }
                }
            }
    }

    var ganttChart: some View {
        // 종일 일정 마커는 body 계산 한 번에 아래 ForEach와 chartOverlay의 tooltipAllDayMarkers 둘 다
        // 필요해서, 한 번만 계산해 두고 재사용한다.
        let allDayMarkers = allDayEventDayMarkers
        let visibleSleepRanges = viewModel.sleepRanges.filter { $0.start < visibleEnd && $0.end > visibleStart }
        let visibleExerciseRanges = viewModel.exerciseRanges.filter { $0.start < visibleEnd && $0.end > visibleStart }
        let visibleCalendarEvents = viewModel.calendarEventRanges.filter {
            !$0.isAllDay && $0.start < visibleEnd && $0.end > visibleStart
        }

        return Chart {
            if !hiddenSeries.contains(.sleep) {
                ForEach(visibleSleepRanges) { interval in
                    let duration = interval.end.timeIntervalSince(interval.start)
                    let isShort = duration < Self.shortSleepThreshold

                    RectangleMark(
                        xStart: .value("수면 시작", interval.start),
                        xEnd: .value("수면 끝", interval.end),
                        yStart: .value("아래", ganttBarYStart),
                        yEnd: .value("위", ganttBarYEnd)
                    )
                    .foregroundStyle((isShort ? Theme.systemRed : sleepColor).opacity(0.7))
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
                ForEach(visibleExerciseRanges) { interval in
                    RectangleMark(
                        xStart: .value("운동 시작", interval.start),
                        xEnd: .value("운동 끝", interval.end),
                        yStart: .value("아래", ganttBarYStart),
                        yEnd: .value("위", ganttBarYEnd)
                    )
                    .foregroundStyle(exerciseColor.opacity(0.7))
                    .cornerRadius(4)
                }
            }

            // 캘린더 일정은 수면/운동과 한 레인에 겹쳐서 표시하되, 시간이 있는 일정과 종일 일정을
            // 다르게 그린다 — 시간 일정은 전체 높이에 옅게 깐 막대, 종일 일정은 겹치는 막대 위에서도
            // 묻히지 않도록 흰 테두리가 있는 원(날짜당 하나)으로 표시한다.
            if !hiddenSeries.contains(.calendarEvent) {
                ForEach(visibleCalendarEvents) { event in
                    RectangleMark(
                        xStart: .value("일정 시작", event.start),
                        xEnd: .value("일정 끝", event.end),
                        yStart: .value("아래", ganttBarYStart),
                        yEnd: .value("위", ganttBarYEnd)
                    )
                    .foregroundStyle(calendarEventColor.opacity(0.35))
                    .cornerRadius(4)
                }

                ForEach(Array(allDayMarkers.enumerated()), id: \.offset) { _, marker in
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

            if visibleDateRange.contains(Date()) {
                RuleMark(x: .value("현재", Date()))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .frame(height: ganttBarsHeight)
        .chartXScale(domain: visibleDateRange)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            ZStack {
                chartOverlay(
                    proxy: proxy,
                    visibleDomain: visibleDomain,
                    yAxisTickValues: [],
                    xAxisTickDates: xAxisTickDates,
                    xAxisLabel: { date in AnyView(xAxisLabel(for: date)) },
                    xAxisLabelBelow: false,
                    showsXAxisLabels: false,
                    showsXAxisBaseline: false,
                    tooltipRanges: hiddenSeries.contains(.calendarEvent) ? [] : visibleCalendarEvents,
                    tooltipSleepRanges: hiddenSeries.contains(.sleep) ? [] : visibleSleepRanges,
                    tooltipWorkoutRanges: hiddenSeries.contains(.exercise) ? [] : visibleExerciseRanges,
                    tooltipAllDayMarkers: hiddenSeries.contains(.calendarEvent) ? [] : allDayMarkers
                )
                ganttBorderOverlay(proxy: proxy)
            }
        }
    }

    // 시간별 모드 전용 — 커피/약복용/이벤트를 시각 축 위의 점(원/별)으로 보여준다. 간트 차트
    // 바로 아래, 회색 구분선으로 나눠서 별도 레인처럼 보이게 한다.
    var hourlyMarkerLane: some View {
        let visibleStart = hrvScrollPosition
        let visibleEnd = hrvScrollPosition.addingTimeInterval(visibleDomain)
        let visibleMarkers = viewModel.dailyMarkers.filter {
            $0.date >= visibleStart
                && $0.date <= visibleEnd
                && ($0.kind != .coffee || !hiddenSeries.contains(.coffee))
                && ($0.kind != .medication || !hiddenSeries.contains(.medication))
                && ($0.kind != .symptom || !hiddenSeries.contains(.symptom))
                && ($0.kind != .event || !hiddenSeries.contains(.lifeEvent))
        }

        return Chart {
            // Chart의 결과 빌더는 ForEach 안에서 케이스마다 다른 조합의 마크/수식어를 쓰는 switch를
            // 잘 못 받아들여 엉뚱한 타입 추론 에러를 낸다 — 마크 하나로 통일하고 모양/색/크기만
            // 종류별로 분기한다.
            ForEach(visibleMarkers) { marker in
                let color = dailyMarkerColor(for: marker.kind)

                // BasicChartSymbolShape엔 별 모양이 없어서(원/사각/세모/다이아몬드/십자 등만 있음),
                // 이벤트만 SF Symbol을 직접 그리는 커스텀 심볼 뷰로 그린다.
                PointMark(x: .value("시간", marker.date), y: .value("위치", 0.5))
                    .symbol {
                        if marker.kind == .event {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(color)
                        } else if marker.kind == .symptom {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(color)
                        } else {
                            Circle()
                                .fill(color)
                                .frame(width: 8, height: 8)
                        }
                    }
            }
        }
        .frame(height: iconLaneHeight)
        .chartXScale(domain: visibleDateRange)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // "그리드"(y축 가로선, gray 0.25)보다 조금 더 진한 회색으로 위쪽에 구분선을 그어서, 위의
        // 간트 막대 레인과 시각적으로 나뉘어 보이게 한다.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(height: 1)
        }
        .chartOverlay { proxy in
            chartOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                yAxisTickValues: [],
                xAxisTickDates: xAxisTickDates,
                xAxisLabel: { date in AnyView(xAxisLabel(for: date)) },
                xAxisLabelBelow: true,
                tooltipDailyMarkers: visibleMarkers
            )
        }
    }

    // 일별 모드 전용 — 간트 차트(수면/운동/캘린더) 대신 안정시 심박수를 하루 막대 하나로 보여준다.
    // 일별 모드는 rMSSD도 이미 하루 대표값(중앙값)이라 같은 결의 "하루 단위 요약" 지표로 맞췄다.
    // 바로 위가 라인 차트라 그 자체로 경계가 보여서, 이 차트만 상단 구분선이 없다.
    var restingHeartRateChart: some View {
        let points = viewModel.wearableRestingHeartRatePointsDaily
        let yAxisUpperBound = max(ceil((points.map(\.value).max() ?? 60) / 20) * 20, 20)

        return dailyBarChart(
            points: points,
            value: \.value,
            valueLabel: "안정시 심박수",
            isHidden: hiddenSeries.contains(.restingHeartRate),
            color: Theme.systemMint,
            yAxisUpperBound: yAxisUpperBound,
            yAxisTicks: yAxisTicks(upperBound: yAxisUpperBound),
            showsTopDivider: false,
            isBottomChart: false
        )
    }

    // 일별 모드 전용 — 오후 9시부터 다음 날 오전 10시까지 실제로 잔 시간만 합산한다.
    // 안정시 심박수 차트 아래에 두고, 이 아래에 일광시간 막대 차트가 하나 더 있어서 x축은 그쪽 최하단
    // 차트에서만 표시한다.
    var nightlySleepChart: some View {
        dailyBarChart(
            points: viewModel.nightlySleepPointsDaily,
            value: \.hours,
            valueLabel: "수면시간",
            isHidden: hiddenSeries.contains(.sleep),
            color: sleepColor,
            yAxisUpperBound: 13,
            yAxisTicks: [0, 4, 8, 12],
            showsTopDivider: true,
            isBottomChart: false
        )
    }

    // 일별 모드 전용 — 수면 차트 아래에 하루 동안 누적된 일광시간(HKQuantityTypeIdentifier.timeInDaylight)을
    // 분 단위 막대로 보여준다. 전체 일별 스택의 x축은 여기(최하단)에서만 표시한다.
    var daylightChart: some View {
        let points = viewModel.daylightPointsDaily
        let yAxisUpperBound = max(ceil((points.map(\.minutes).max() ?? 60) / 30) * 30, 30)
        // 분 단위 값이라 rMSSD/안정시 심박수용 50 간격 눈금(yAxisTicks)은 안 맞아서, 위/아래 두 눈금만
        // 직접 잡는다.
        let daylightYAxisTicks = [0, yAxisUpperBound / 2, yAxisUpperBound]

        return dailyBarChart(
            points: points,
            value: \.minutes,
            valueLabel: "일광시간",
            isHidden: hiddenSeries.contains(.daylight),
            color: Theme.systemYellow,
            yAxisUpperBound: yAxisUpperBound,
            yAxisTicks: daylightYAxisTicks,
            showsTopDivider: true,
            isBottomChart: true
        )
    }

    // 월별 모드는 위쪽에 rMSSD 1Q~3Q와 중앙값을, 아래쪽에는 그 달의 CV를 보여준다.
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
                    // 핀치 줌으로 "보이는 달의 개수"가 바뀌면 bandwidth도 바뀌므로 다시 계산한다.
                    // visibleDomain 자체(연속값)가 아니라 개수(정수)로 감지해야, 핀치하는 동안 매
                    // 프레임 눈금을 다시 계산하고 또 렌더링하는 낭비 없이 실제로 달 하나가 더 보이거나
                    // 덜 보일 때만 갱신된다.
                    .onChange(of: monthlyTickDates.count) { _, _ in
                        updateMonthlyBarWidth(plotWidth: geo.size.width)
                    }
            }
        }
        // lineAndGanttChartsStack과 같은 이유로, 캔들스틱+CV 차트를 합친 전체 영역에 한 번만 붙인다.
        .contentShape(Rectangle())
        .simultaneousGesture(magnifyToZoomGesture)
    }

    private var monthlyCandlestickChart: some View {
        let range = cachedRange
        // 이상치 하나가 몇 백ms로 튀면 나머지 달들이 축 아래쪽에 짜부라져 보이므로, 150에서 자른다.
        let yAxisUpperBound = min(
            max(ceil(range.max / 50) * 50, 50),
            Self.maximumRMSSDChartValue
        )

        return Chart {
            if !hiddenSeries.contains(.rmssd) {
                ForEach(viewModel.wearableRMSSDMonthlyStats) { stat in
                    // 1Q~3Q 구간을 연보라 사각형으로 표시한다.
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
                ForEach(visibleExamPoints) { point in
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
        .chartXScale(domain: visibleDateRange)
        .chartYScale(domain: 0...yAxisUpperBound)
        .chartPlotStyle { $0.clipped() }
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
        .chartXScale(domain: visibleDateRange)
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
        monthlyBarWidth = (bandwidth * 0.5).clamped(to: 10...30) * 0.7
    }
}
