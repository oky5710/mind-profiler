import Charts
import SwiftUI

// 커스텀 축/스크롤/툴팁 오버레이. Swift Charts 기본 축은 y축 라벨 너비만큼 플롯 영역을 줄이고,
// 내장 chartScrollableAxes는 이 화면 조합(다중 Chart + 커스텀 축)에서 반응하지 않아 전부 직접 구현했다.
extension HRVAnalysisView {
    // 이 값보다 적게 움직인 드래그만 "탭"으로 보고 툴팁을 갱신한다 — 그 이상은 스크롤 의도로 본다.
    private static let tooltipDragTolerance: CGFloat = 4

    // y축 라벨이 차트 레이아웃 공간을 차지하지 않고 고정된 위치에 떠 있어야 한다는 규칙(ui-style.md) 때문에,
    // 기본 제공되는 leading y축(라벨 너비만큼 플롯 영역을 줄임) 대신 y축은 숨기고 직접 오버레이로 그린다.
    func yAxisTicks(upperBound: Double) -> [Double] {
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

    func chartOverlay(
        proxy: ChartProxy,
        visibleDomain: TimeInterval,
        yAxisTickValues: [Double],
        xAxisTickDates: [Date],
        xAxisLabel: @escaping (Date) -> AnyView,
        xAxisLabelPositionDate: @escaping (Date) -> Date = { $0 },
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = [],
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = [],
        tooltipSleepRanges: [SleepRange] = [],
        tooltipWorkoutRanges: [HRVAnalysisViewModel.WorkoutRange] = [],
        tooltipAllDayMarkers: [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] = []
    ) -> some View {
        ZStack {
            xAxisOverlay(proxy: proxy, tickDates: xAxisTickDates, label: xAxisLabel, labelPositionDate: xAxisLabelPositionDate)
            yAxisOverlay(proxy: proxy, tickValues: yAxisTickValues)
            dragToScrollOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                tooltipPoints: tooltipPoints,
                tooltipRanges: tooltipRanges,
                tooltipSleepRanges: tooltipSleepRanges,
                tooltipWorkoutRanges: tooltipWorkoutRanges,
                tooltipAllDayMarkers: tooltipAllDayMarkers
            )
        }
    }

    // 선택된 Gantt 막대(캘린더 일정/수면 구간) 강조용 그림자 도형 — 차트 마크 자체는 shadow()를
    // 지원하지 않아서, 같은 위치·크기·색으로 진짜 SwiftUI 도형을 하나 더 겹쳐 그려서 대신 그림자를 준다.
    @ViewBuilder
    private func selectionShadow(start: Date, end: Date, color: Color, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame,
           let x0 = proxy.position(forX: start), let x1 = proxy.position(forX: end),
           let y0 = proxy.position(forY: 0.0), let y1 = proxy.position(forY: 1.0) {
            let plotRect = geo[plotFrame]
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: abs(x1 - x0), height: abs(y1 - y0))
                .position(x: plotRect.minX + (x0 + x1) / 2, y: plotRect.minY + (y0 + y1) / 2)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .allowsHitTesting(false)
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
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = [],
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = [],
        tooltipSleepRanges: [SleepRange] = [],
        tooltipWorkoutRanges: [HRVAnalysisViewModel.WorkoutRange] = [],
        tooltipAllDayMarkers: [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] = []
    ) -> some View {
        // 툴팁 말풍선이 화면/차트 밖으로 나가지 않도록, 세로선 자체는 실제 위치에 그리되
        // 말풍선의 x 위치만 플롯 안쪽으로 밀어 넣는다 (말풍선 예상 반너비만큼 여유를 둠).
        let estimatedTooltipHalfWidth: CGFloat = 45
        // 종일 일정 원은 탭 지점이 그 원에서 이만큼(포인트) 이내일 때만 반응한다 — 그 날 전체가 아니라
        // 실제로 원을 눌렀을 때만 툴팁이 뜨게 하기 위함.
        let allDayMarkerHitRadius: CGFloat = 16

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

                // 캘린더/수면 툴팁은 간트 차트 안에 그리지 않는다 — 어떤 일정/수면 구간이 선택됐는지만
                // (tooltipCalendarEvent/tooltipSleepRange) 여기서 판정하고, 실제 상세 패널은
                // HRVAnalysisView.swift의 selectedItemDetailPanel이 간트 차트 아래 전체 폭으로 그린다.
                // 대신 선택된 막대에는 그림자를 준다 — 차트 마크 자체는 shadow()를 지원하지 않아서,
                // 같은 위치·크기·색으로 진짜 SwiftUI 도형을 하나 더 겹쳐 그려서 그 도형에 그림자를 준다.
                if !tooltipRanges.isEmpty, let event = tooltipCalendarEvent, !event.isAllDay {
                    selectionShadow(start: event.start, end: event.end, color: calendarEventColor, proxy: proxy, geo: geo)
                }

                if !tooltipSleepRanges.isEmpty, let sleepRange = tooltipSleepRange {
                    let isShort = sleepRange.end.timeIntervalSince(sleepRange.start) < Self.shortSleepThreshold
                    selectionShadow(start: sleepRange.start, end: sleepRange.end, color: isShort ? .red : sleepColor, proxy: proxy, geo: geo)
                }

                if !tooltipWorkoutRanges.isEmpty, let workoutRange = tooltipWorkoutRange {
                    selectionShadow(start: workoutRange.start, end: workoutRange.end, color: exerciseColor, proxy: proxy, geo: geo)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        // minimumDistance: 0 — 손가락을 움직이지 않는 단순 탭에서도 onChanged가 즉시 발생해야
                        // 툴팁/세로선이 뜬다. 이동량이 커지면(스크롤 의도) 아래에서 툴팁을 감춘다.
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // 핀치 줌이 진행 중일 때는 그 첫 손가락이 만든 드래그가 스크롤/툴팁과
                                // 뒤섞이지 않도록 무시한다.
                                guard !isZooming else { return }
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
                                let maxStart = latestVisibleEnd(for: chartMode).addingTimeInterval(-visibleDomain)
                                hrvScrollPosition = min(proposed, maxStart)

                                // 실제로 스크롤하려고 손가락을 움직이는 중에는 툴팁을 감춘다 — 계속 값이
                                // 바뀌면서 스크롤과 툴팁 갱신이 뒤섞여 산만해지는 걸 막는다. 제자리에 가까운
                                // 탭(이동량이 작음)일 때만 툴팁을 갱신한다.
                                guard abs(value.translation.width) <= Self.tooltipDragTolerance else {
                                    tooltipPoint = nil
                                    tooltipCalendarEvent = nil
                                    tooltipSleepRange = nil
                                    tooltipWorkoutRange = nil
                                    return
                                }

                                if !tooltipPoints.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipPoint = tooltipPoints.min {
                                            abs($0.date.timeIntervalSince(touchedDate)) < abs($1.date.timeIntervalSince(touchedDate))
                                        }
                                    }
                                }

                                // 이 차트가 캘린더/수면 툴팁을 아예 다루지 않으면(라인 차트, 월별 차트),
                                // 여기를 탭했을 때 다른 차트에서 열려 있던 캘린더/수면 툴팁은 무조건 닫는다 —
                                // "툴팁이 아닌 곳을 클릭하면 무조건 닫힌다"를 모든 차트에서 보장하기 위함.
                                if !tooltipRanges.isEmpty || !tooltipAllDayMarkers.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    var matchedEvent: HRVAnalysisViewModel.CalendarEventRange?

                                    if !tooltipRanges.isEmpty, let touchedDate: Date = proxy.value(atX: localX) {
                                        matchedEvent = tooltipRanges.first {
                                            $0.start <= touchedDate && touchedDate <= $0.end
                                        }
                                    }

                                    // 종일 일정 원은 "그날 어디를 눌러도" 반응하면 다른 날의 원을 확인하기
                                    // 어려워지므로, 가장 가까운 원이더라도 실제 반경 안에 들어왔을 때만 인정한다.
                                    if matchedEvent == nil, !tooltipAllDayMarkers.isEmpty,
                                       let nearest = tooltipAllDayMarkers.min(by: { a, b in
                                           abs((proxy.position(forX: a.day) ?? .infinity) - localX)
                                               < abs((proxy.position(forX: b.day) ?? .infinity) - localX)
                                       }) {
                                        let nearestX = proxy.position(forX: nearest.day) ?? .infinity
                                        if abs(nearestX - localX) <= allDayMarkerHitRadius {
                                            matchedEvent = nearest.event
                                        }
                                    }

                                    tooltipCalendarEvent = matchedEvent
                                } else {
                                    tooltipCalendarEvent = nil
                                }

                                if !tooltipSleepRanges.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipSleepRange = tooltipSleepRanges.first {
                                            $0.start <= touchedDate && touchedDate <= $0.end
                                        }
                                    }
                                } else {
                                    tooltipSleepRange = nil
                                }

                                if !tooltipWorkoutRanges.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipWorkoutRange = tooltipWorkoutRanges.first {
                                            $0.start <= touchedDate && touchedDate <= $0.end
                                        }
                                    }
                                } else {
                                    tooltipWorkoutRange = nil
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

    // MARK: - 핀치 줌
    // 두 손가락 핀치로 visibleDomain을 chartMode 기본값의 0.5~5배 범위에서 연속적으로 조절한다.
    // 확대/축소하는 동안 제스처 시작 시점의 "화면 중앙 시각"을 고정점으로 유지해서, 배율이 바뀌어도
    // 보고 있던 지점이 화면 밖으로 튀지 않고 그 자리에서 확대/축소되는 것처럼 보인다.
    // 라인/간트 차트가 각자 별도의 Chart(overlay)라서, 이 제스처를 그 안쪽 개별 오버레이에 붙이면
    // 핀치의 두 손가락이 서로 다른 차트(다른 view) 위에 떨어졌을 때 한 번의 핀치로 인식되지 않고
    // 각 차트가 손가락 하나짜리 드래그로 오인해서 서로 뒤섞인 채로 반응한다. 그래서 이 제스처는 proxy가
    // 필요 없다는 점을 이용해 두 차트를 함께 감싸는 상위 컨테이너(lineAndGanttChartsStack/monthlyChart)에
    // 딱 한 번만 붙인다 — 손가락이 어느 차트 위에 있든 같은 제스처 인식기가 처리한다.
    var magnifyToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomAnchorScale == nil {
                    zoomAnchorScale = zoomScale
                    zoomAnchorCenterDate = hrvScrollPosition.addingTimeInterval(visibleDomain / 2)
                    isZooming = true
                    dragAnchorPosition = nil
                    tooltipPoint = nil
                    tooltipCalendarEvent = nil
                    tooltipSleepRange = nil
                    tooltipWorkoutRange = nil
                }
                guard let anchorScale = zoomAnchorScale, let centerDate = zoomAnchorCenterDate else { return }
                let proposedScale = anchorScale * value
                zoomScale = min(max(proposedScale, HRVAnalysisView.minZoomScale), HRVAnalysisView.maxZoomScale)

                // 한계에 "새로 닿았을 때"만 토스트를 띄운다 — 안 그러면 한계에 붙어있는 동안 매 프레임
                // 다시 띄워져서 애니메이션이 끊임없이 재시작된다.
                let hitMax = proposedScale > HRVAnalysisView.maxZoomScale
                let hitMin = proposedScale < HRVAnalysisView.minZoomScale
                if hitMax, !isZoomAtMax {
                    toastCenter.show("최대로 확대되었습니다", type: .info)
                }
                if hitMin, !isZoomAtMin {
                    toastCenter.show("최대로 축소되었습니다", type: .info)
                }
                isZoomAtMax = hitMax
                isZoomAtMin = hitMin

                let newDomain = chartMode.visibleDomain / Double(zoomScale)
                let maxStart = latestVisibleEnd(for: chartMode).addingTimeInterval(-newDomain)
                hrvScrollPosition = min(centerDate.addingTimeInterval(-newDomain / 2), maxStart)
            }
            .onEnded { _ in
                zoomAnchorScale = nil
                zoomAnchorCenterDate = nil
                isZooming = false
                isZoomAtMax = false
                isZoomAtMin = false
            }
    }

    // 라인 차트와 간트 차트가 같은 hrvScrollPosition/visibleDomain을 쓰더라도, 각자 알아서
    // "automatic" 눈금을 고르면 서로 다른 위치에 눈금이 생길 수 있어 명시적으로 동일한 눈금 배열을 계산해서 공유함.
    // 그리드 눈금은 "정시"에만 찍혀야 한다 — 일별은 자정(00시)에만, 시간별은 분이 00일 때만.
    // hrvScrollPosition 자체는 "지금부터 visibleDomain 이전" 같은 임의 시각이라 그대로 stride를 더하면
    // 14:23, 18:23 처럼 어중간한 시각에 눈금이 찍히므로, 시작점을 가장 가까운 깨끗한 경계로 올림한다.
    var xAxisTickDates: [Date] {
        let calendar = Calendar.current
        let end = hrvScrollPosition.addingTimeInterval(visibleDomain)

        switch chartMode {
        case .hourly:
            let strideHours = 4
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: hrvScrollPosition)
            components.minute = 0
            components.second = 0
            guard var current = calendar.date(from: components) else { return [] }
            if current < hrvScrollPosition {
                current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current
            }
            while calendar.component(.hour, from: current) % strideHours != 0 {
                guard let next = calendar.date(byAdding: .hour, value: 1, to: current) else { break }
                current = next
            }

            var dates: [Date] = []
            while current <= end {
                dates.append(current)
                guard let next = calendar.date(byAdding: .hour, value: strideHours, to: current) else { break }
                current = next
            }
            return dates

        case .daily:
            let strideDays = 3
            var current = calendar.startOfDay(for: hrvScrollPosition)
            if current < hrvScrollPosition {
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }

            var dates: [Date] = []
            while current <= end {
                dates.append(current)
                guard let next = calendar.date(byAdding: .day, value: strideDays, to: current) else { break }
                current = next
            }
            return dates

        case .monthly:
            // baseLineChart/ganttChart는 monthly 모드에서 쓰이지 않으므로(monthlyChart가 별도 처리) 실제로는
            // 호출되지 않지만, switch 전체 커버를 위해 남겨둔다.
            return []
        }
    }

    func xAxisLabel(for date: Date) -> some View {
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
    var monthlyTickDates: [Date] {
        let calendar = Calendar.current
        let end = hrvScrollPosition.addingTimeInterval(visibleDomain)
        var dates: [Date] = []
        var current = calendar.dateInterval(of: .month, for: hrvScrollPosition)?.start ?? hrvScrollPosition
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    func monthlyAxisLabel(for date: Date) -> some View {
        Text(Self.monthFormatter.string(from: date))
            .bold()
            .font(.system(size: 9))
            .tracking(1)
    }

    // 캔들스틱 마크는 x: .value(_, monthStart, unit: .month)로 그 달 전체 구간에 걸쳐 묶여서,
    // 실제로는 달의 시작이 아니라 그 구간 중앙(대략 보름)에 그려진다 — 라벨도 같은 좌표를 쓰게
    // 이 중앙 시각을 계산한다.
    func monthMidpoint(of date: Date) -> Date {
        guard let interval = Calendar.current.dateInterval(of: .month, for: date) else { return date }
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    // x축 라벨도 y축과 같은 이유(ui-style.md)로 레이아웃 공간을 차지하지 않고 차트 안에 고정 위치로 띄운다.
    private func xAxisOverlay(
        proxy: ChartProxy,
        tickDates: [Date],
        label: @escaping (Date) -> AnyView,
        labelPositionDate: @escaping (Date) -> Date = { $0 }
    ) -> some View {
        GeometryReader { geo in
            if let plotFrame = proxy.plotFrame {
                let plotRect = geo[plotFrame]

                // 라벨 간격이 실제 라벨 텍스트 너비(9pt, "MM-dd"/"HH:mm" 기준 약 40px)보다 좁아져
                // 겹칠 것 같으면 뒤쪽 라벨은 생략한다 (그리드 선은 계속 그림). 틱 간격은 시간 단위로
                // 고정이라, 핀치로 축소해서 같은 폭에 더 넓은 기간이 들어오면 틱 사이 픽셀 간격이
                // 좁아지는데 — 축소 방향에서도 이 규칙이 그대로 적용되어 라벨이 겹치지 않는다.
                let minLabelSpacing: CGFloat = 40
                var lastLabelX: CGFloat?
                let visibleLabelDates: Set<Date> = Set(tickDates.compactMap { date -> Date? in
                    guard let x = proxy.position(forX: date) else { return nil }
                    if let last = lastLabelX, x - last < minLabelSpacing { return nil }
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

                            // 월별 캔들스틱처럼 마크가 unit(예: .month) 단위로 묶여서 눈금의 정확한
                            // 시각이 아니라 그 구간 중앙에 그려지는 경우, 라벨도 같은 중앙 좌표를
                            // 쓰도록 labelPositionDate로 별도 계산한다(그리드 선은 눈금 그대로).
                            if visibleLabelDates.contains(date), let labelX = proxy.position(forX: labelPositionDate(date)) {
                                label(date)
                                    .padding(.horizontal, 3)
                                    .position(x: plotRect.minX + labelX, y: plotRect.maxY - 10)
                            }
                        }
                    }
                }
            }
        }
    }
}
