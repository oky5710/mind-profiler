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
        tooltipPoints: [HRVAnalysisViewModel.HRVPoint] = [],
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = [],
        tooltipSleepRanges: [SleepRange] = [],
        tooltipAllDayMarkers: [(day: Date, event: HRVAnalysisViewModel.CalendarEventRange)] = []
    ) -> some View {
        ZStack {
            xAxisOverlay(proxy: proxy, tickDates: xAxisTickDates, label: xAxisLabel)
            yAxisOverlay(proxy: proxy, tickValues: yAxisTickValues)
            dragToScrollOverlay(
                proxy: proxy,
                visibleDomain: visibleDomain,
                tooltipPoints: tooltipPoints,
                tooltipRanges: tooltipRanges,
                tooltipSleepRanges: tooltipSleepRanges,
                tooltipAllDayMarkers: tooltipAllDayMarkers
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
        tooltipRanges: [HRVAnalysisViewModel.CalendarEventRange] = [],
        tooltipSleepRanges: [SleepRange] = [],
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
                if !tooltipRanges.isEmpty, let event = tooltipCalendarEvent, !event.isAllDay,
                   let plotFrame = proxy.plotFrame,
                   let x0 = proxy.position(forX: event.start), let x1 = proxy.position(forX: event.end),
                   let y0 = proxy.position(forY: 0.0), let y1 = proxy.position(forY: 1.0) {
                    let plotRect = geo[plotFrame]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(calendarEventColor)
                        .frame(width: abs(x1 - x0), height: abs(y1 - y0))
                        .position(x: plotRect.minX + (x0 + x1) / 2, y: plotRect.minY + (y0 + y1) / 2)
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                        .allowsHitTesting(false)
                }

                if !tooltipSleepRanges.isEmpty, let sleepRange = tooltipSleepRange,
                   let plotFrame = proxy.plotFrame,
                   let x0 = proxy.position(forX: sleepRange.start), let x1 = proxy.position(forX: sleepRange.end),
                   let y0 = proxy.position(forY: 0.0), let y1 = proxy.position(forY: 1.0) {
                    let plotRect = geo[plotFrame]
                    let isShort = sleepRange.end.timeIntervalSince(sleepRange.start) < Self.shortSleepThreshold
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isShort ? Color.red : sleepColor)
                        .frame(width: abs(x1 - x0), height: abs(y1 - y0))
                        .position(x: plotRect.minX + (x0 + x1) / 2, y: plotRect.minY + (y0 + y1) / 2)
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        // minimumDistance: 0 — 손가락을 움직이지 않는 단순 탭에서도 onChanged가 즉시 발생해야
                        // 툴팁/세로선이 뜬다. 이동량이 커지면(스크롤 의도) 아래에서 툴팁을 감춘다.
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

                                // 실제로 스크롤하려고 손가락을 움직이는 중에는 툴팁을 감춘다 — 계속 값이
                                // 바뀌면서 스크롤과 툴팁 갱신이 뒤섞여 산만해지는 걸 막는다. 제자리에 가까운
                                // 탭(이동량이 작음)일 때만 툴팁을 갱신한다.
                                guard abs(value.translation.width) <= Self.tooltipDragTolerance else {
                                    tooltipPoint = nil
                                    tooltipCalendarEvent = nil
                                    tooltipSleepRange = nil
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
                                }

                                if !tooltipSleepRanges.isEmpty {
                                    let localX = value.location.x - plotRect.minX
                                    if let touchedDate: Date = proxy.value(atX: localX) {
                                        tooltipSleepRange = tooltipSleepRanges.first {
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
                                    .position(x: plotRect.minX + x, y: plotRect.maxY - 10)
                            }
                        }
                    }
                }
            }
        }
    }
}
