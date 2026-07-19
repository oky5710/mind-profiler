import Charts
import SwiftUI

// 커스텀 축/스크롤/툴팁 오버레이. Swift Charts 기본 축은 y축 라벨 너비만큼 플롯 영역을 줄이고,
// 내장 chartScrollableAxes는 이 화면 조합(다중 Chart + 커스텀 축)에서 반응하지 않아 전부 직접 구현했다.
extension HRVAnalysisView {
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
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = [],
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = []
    ) -> some View {
        ZStack {
            xAxisOverlay(proxy: proxy, tickDates: xAxisTickDates, label: xAxisLabel)
            yAxisOverlay(proxy: proxy, tickValues: yAxisTickValues)
            dragToScrollOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                tooltipPoints: tooltipPoints,
                tooltipRanges: tooltipRanges
            )
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
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = []
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

                // 캘린더 일정 툴팁은 포인트 툴팁과 달리 "탭한 위치가 그 일정 막대 안에 있는지"로
                // 판단한다 (가장 가까운 값이 아니라 실제로 그 구간을 눌렀는지가 중요).
                if !tooltipRanges.isEmpty,
                   let event = tooltipCalendarEvent,
                   let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: event.start) {
                    let plotRect = geo[plotFrame]
                    let clampedLocalX = min(
                        max(x, estimatedTooltipHalfWidth),
                        max(plotRect.width - estimatedTooltipHalfWidth, estimatedTooltipHalfWidth)
                    )
                    tooltipLabel(for: event)
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
                                let maxStart = latestVisibleEnd(for: chartMode).addingTimeInterval(-visibleDomain)
                                hrvScrollPosition = min(proposed, maxStart)

                                if !tooltipPoints.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipPoint = tooltipPoints.min {
                                            abs($0.date.timeIntervalSince(touchedDate)) < abs($1.date.timeIntervalSince(touchedDate))
                                        }
                                    }
                                }

                                if !tooltipRanges.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipCalendarEvent = tooltipRanges.first {
                                            $0.start <= touchedDate && touchedDate <= $0.end
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
    // 그리드 눈금은 "정시"에만 찍혀야 한다 — 일별은 자정(00시)에만, 시간별은 분이 00일 때만.
    // hrvScrollPosition 자체는 "지금부터 visibleDomain 이전" 같은 임의 시각이라 그대로 stride를 더하면
    // 14:23, 18:23 처럼 어중간한 시각에 눈금이 찍히므로, 시작점을 가장 가까운 깨끗한 경계로 올림한다.
    var xAxisTickDates: [Date] {
        let calendar = Calendar.current
        let end = hrvScrollPosition.addingTimeInterval(chartMode.visibleDomain)

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

    func monthlyAxisLabel(for date: Date) -> some View {
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
}
