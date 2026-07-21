import Charts
import SwiftUI

enum HRVChartMode: String, CaseIterable {
    case hourly = "시간별"
    case daily = "일별"
    case monthly = "월별"

    var visibleDomain: TimeInterval {
        switch self {
        case .hourly: 24 * 60 * 60
        case .daily: 30 * 24 * 60 * 60
        // 달 하나가 화면에서 차지하는 폭 자체를 70%로 줄여달라는 요청 — 같은 화면 폭에 더 많은
        // 달이 보이면 달 하나의 대역폭(bandwidth)이 그만큼 좁아지므로, 보이는 기간을 1/0.7배로 늘린다.
        case .monthly: (4 * 30 * 24 * 60 * 60) / 0.7
        }
    }

    var iconName: String {
        switch self {
        case .hourly: "clock"
        case .daily: "calendar"
        case .monthly: "chart.bar"
        }
    }
}

// 범례에 나오는 지표 단위. 범례를 탭하면 hiddenSeries에 넣고 빼서 차트에서 보이기/숨기기를 토글한다.
enum HRVSeries: String, CaseIterable, Identifiable {
    case rmssd, examRmssd, sleep, exercise, median, sdnn, calendarEvent, cv
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rmssd: "rMSSD (계산값)"
        case .examRmssd: "검사 rMSSD"
        case .sleep: "수면"
        case .exercise: "운동"
        case .median: "최근 30일 중앙값"
        case .sdnn: "SDNN"
        case .calendarEvent: "캘린더"
        case .cv: "변동계수 (CV)"
        }
    }

    var symbol: String {
        switch self {
        case .rmssd: "circle.fill"
        case .examRmssd: "triangle.fill"
        case .sleep: "square.fill"
        case .exercise: "square.fill"
        case .median: "minus"
        case .sdnn: "minus"
        case .calendarEvent: "square.fill"
        case .cv: "chart.bar.fill"
        }
    }

    // 시간별/일별/월별 모드가 서로 다른 차트 조합을 그리므로, 그 모드에서 실제로
    // 영향을 주는 지표만 범례에 노출한다 — 안 그러면 토글해도 아무 변화가 없는 항목이 보인다.
    func appliesTo(_ mode: HRVChartMode) -> Bool {
        switch self {
        case .rmssd, .examRmssd, .median: true
        case .sdnn: mode == .hourly
        case .sleep, .exercise, .calendarEvent: mode != .monthly
        case .cv: mode == .monthly
        }
    }
}

struct HRVAnalysisView: View {
    // 핀치 줌 배율 범위. 1.0이 chartMode의 기본 visibleDomain이고, 배율이 커질수록(최대 5배)
    // 화면에 보이는 기간이 좁아지고(확대), 작아질수록(최소 0.5배) 넓어진다(축소).
    static let minZoomScale: CGFloat = 0.5
    static let maxZoomScale: CGFloat = 5.0

    @State var viewModel = HRVAnalysisViewModel()
    @State var chartMode: HRVChartMode = .hourly
    @State var hrvScrollPosition = Date().addingTimeInterval(-HRVChartMode.hourly.visibleDomain)
    @State var dragAnchorPosition: Date?
    @State var zoomScale: CGFloat = 1.0
    @State var zoomAnchorScale: CGFloat?
    @State var zoomAnchorCenterDate: Date?
    @Environment(ToastCenter.self) var toastCenter
    @State var hiddenSeries: Set<HRVSeries> = []
    @State var tooltipPoint: HRVAnalysisViewModel.HRVPoint?
    @State var tooltipCalendarEvent: HRVAnalysisViewModel.CalendarEventRange?
    @State var tooltipSleepRange: SleepRange?
    @State var tooltipWorkoutRange: HRVAnalysisViewModel.WorkoutRange?

    // hrvScrollPosition이 스크롤 중 계속 바뀌는데, 매 프레임 body가 다시 계산될 때마다
    // 전체 포인트를 다시 스캔하면 스크롤이 심하게 느려져서 모드/데이터가 바뀔 때만 갱신.
    @State var cachedRange: (min: Double, max: Double) = (0, 100)
    // UIKit(UIScreen) 없이 화면 높이를 구하기 위해 GeometryReader로 실측한다 (AGENTS.md: UIKit 사용 금지).
    // 처음 그려질 때는 아직 측정 전이라 흔한 화면 높이로 잠깐 대체했다가, onAppear에서 바로 갱신된다.
    @State var availableHeight: CGFloat = 850
    // 월별 막대 너비 = bandwidth(월 하나가 차지하는 폭)의 50%, 10~30px로 clamp. 실측 전 기본값.
    @State var monthlyBarWidth: CGFloat = 20

    let rmssdColor = Theme.rmssd
    let examRmssdColor = Theme.examRmssd
    let exerciseColor = Theme.exercise
    let sleepColor = Theme.sleep
    let calendarEventColor = Theme.systemBlue

    static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static let monthFormatter: DateFormatter = {
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

    var currentRMSSDPoints: [HRVAnalysisViewModel.HRVPoint] {
        switch chartMode {
        case .hourly: viewModel.wearableRMSSDPointsHourly
        case .daily: viewModel.wearableRMSSDPointsDaily
        case .monthly: []
        }
    }

    // chartMode의 기본 기간을 zoomScale로 나눈 실제 표시 기간 — 핀치 줌으로 연속적으로 변한다.
    var visibleDomain: TimeInterval {
        chartMode.visibleDomain / Double(zoomScale)
    }

    // 각 차트의 `.chartXScale(domain:)`가 전부 이 범위를 그대로 쓴다.
    var visibleDateRange: ClosedRange<Date> {
        hrvScrollPosition...hrvScrollPosition.addingTimeInterval(visibleDomain)
    }

    // zoomAnchorScale이 있다는 것 자체가 핀치가 진행 중이라는 뜻이라 별도 상태로 안 둔다.
    var isZooming: Bool {
        zoomAnchorScale != nil
    }

    private var hasAnyLineChartData: Bool {
        !currentRMSSDPoints.isEmpty
            || !viewModel.examPoints.isEmpty
            || !viewModel.sleepRanges.isEmpty
            || !viewModel.exerciseRanges.isEmpty
            || !viewModel.calendarEventRanges.isEmpty
    }

    // ui-style.md 규칙: 차트 높이는 전체 화면의 40%. 간트 차트는 그 절반의 70%.
    var lineChartHeight: CGFloat {
        availableHeight * 0.4
    }

    var ganttChartHeight: CGFloat {
        lineChartHeight / 2 * 0.7
    }

    // 시간별/일별은 "지금"까지만 스크롤 가능하지만, 월별은 이번 달이 아직 안 끝났어도 이번 달 데이터가
    // 잘리지 않고 보여야 하므로 이번 달의 마지막 날까지 스크롤할 수 있어야 한다.
    func latestVisibleEnd(for mode: HRVChartMode) -> Date {
        switch mode {
        case .hourly, .daily:
            return Date()
        case .monthly:
            let now = Date()
            return Calendar.current.dateInterval(of: .month, for: now)?.end ?? now
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
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
                    tooltipCalendarEvent = nil
                    tooltipSleepRange = nil
                    tooltipWorkoutRange = nil
                }
                .onAppear { availableHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, newHeight in availableHeight = newHeight }
            }
            .navigationTitle("오늘의 패턴")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
            recomputeRange()
        }
        .task {
            if await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd) {
                recomputeRange()
            }
        }
        .task {
            await viewModel.loadRecentThirtyDayMedianIfNeeded()
        }
        .task {
            await viewModel.loadCalendarEventsIfNeeded()
        }
        // 스크롤(드래그)이나 핀치 줌으로 보이는 구간이 바뀔 때마다 호출하지만, 이미 여유 있게
        // 로드된 범위 안이면 ensureHealthKitDataLoaded가 그냥 바로 반환하므로 실제 HealthKit
        // 조회는 가장자리에 가까워질 때만 드물게 일어난다.
        .onChange(of: hrvScrollPosition) { _, _ in
            Task {
                if await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd) {
                    recomputeRange()
                }
            }
        }
        .onChange(of: visibleDomain) { _, _ in
            Task {
                if await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd) {
                    recomputeRange()
                }
            }
        }
        .onChange(of: chartMode) { _, newMode in
            resetZoom(for: newMode)
            tooltipPoint = nil
            tooltipCalendarEvent = nil
            tooltipSleepRange = nil
            tooltipWorkoutRange = nil
            recomputeRange()
        }
        .refreshable {
            await viewModel.reload()
            // 지금 보이는 구간은 pull-to-refresh니까 이미 로드돼 있어도(force) 무조건 다시 불러온다 —
            // 워치에서 새로 동기화된 데이터가 있을 수 있어서다.
            await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd, force: true)
            await viewModel.loadCalendarEventsIfNeeded()
            recomputeRange()
        }
    }

    private var visibleStart: Date { hrvScrollPosition }
    private var visibleEnd: Date { hrvScrollPosition.addingTimeInterval(visibleDomain) }

    // 핀치 줌 상태를 mode의 기본 배율(1배)로 되돌리고, 스크롤 위치도 그 모드의 "가장 최근 구간"으로
    // 되돌린다 — 모드 전환 시(onChange)와 왼쪽 리셋 버튼 탭 시 둘 다 여기서 처리한다.
    private func resetZoom(for mode: HRVChartMode) {
        zoomScale = 1.0
        clearZoomAnchor()
        hrvScrollPosition = latestVisibleEnd(for: mode).addingTimeInterval(-mode.visibleDomain)
    }

    // 핀치가 끝났을 때(onEnded)와 리셋할 때 둘 다 앵커를 지워야 해서 공통으로 뺐다.
    func clearZoomAnchor() {
        zoomAnchorScale = nil
        zoomAnchorCenterDate = nil
    }

    private func recomputeRange() {
        var values = viewModel.examPoints.map(\.rmssd)
        switch chartMode {
        case .hourly:
            values += currentRMSSDPoints.map(\.value)
            if !hiddenSeries.contains(.sdnn) {
                values += viewModel.wearableSDNNPointsHourly.map(\.value)
            }
        case .daily:
            values += currentRMSSDPoints.map(\.value)
        case .monthly:
            values += viewModel.wearableRMSSDMonthlyStats.flatMap { [$0.min, $0.max] }
        }
        cachedRange = values.isEmpty ? (min: 0.0, max: 100.0) : (min: values.min()!, max: values.max()!)
    }

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HRV Trend").font(.system(size: 13.6, weight: .semibold))
                Spacer()
                // 핀치로 확대/축소한 뒤 원래 배율(1배)로 되돌리는 버튼. 이미 원래 배율이면 눌러도
                // 할 일이 없으니 흐리게 표시하고 탭을 막는다 — 그래도 자리는 계속 차지해서 픽커 옆
                // 레이아웃이 줌 상태에 따라 흔들리지 않는다.
                Button {
                    resetZoom(for: chartMode)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(zoomScale == 1.0)
                .opacity(zoomScale == 1.0 ? 0.35 : 1)
                .padding(.trailing, 8)

                Picker("보기 단위", selection: $chartMode) {
                    ForEach(HRVChartMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.iconName)
                            .accessibilityLabel(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.bottom, 20)

            hrvChartBody
        }
    }

    func tooltipLabel(for point: HRVAnalysisViewModel.HRVPoint) -> some View {
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

    func tooltipLabel(for event: HRVAnalysisViewModel.CalendarEventRange) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if event.category != .general {
                Text(event.category == .holiday ? "공휴일" : "휴가")
                    .font(.caption2.bold())
                    .foregroundStyle(allDayEventColor(for: event.category))
            }
            Text(event.title)
                .font(.subheadline.bold())
            Text(calendarEventTimeRangeText(event))
                .font(.caption2)
            if let location = event.location, !location.isEmpty {
                Text(location)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        // 라이트 모드에서는 배경이 흰색에 가까워 테두리가 없으면 툴팁이 안 보일 수 있다.
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private func calendarEventTimeRangeText(_ event: HRVAnalysisViewModel.CalendarEventRange) -> String {
        if event.isAllDay {
            return "\(Self.monthDayFormatter.string(from: event.start)) 종일"
        }
        return "\(Self.tooltipDateFormatter.string(from: event.start)) ~ \(Self.hourMinuteFormatter.string(from: event.end))"
    }

    func tooltipLabel(for workout: HRVAnalysisViewModel.WorkoutRange) -> some View {
        let duration = workout.end.timeIntervalSince(workout.start)

        return VStack(alignment: .leading, spacing: 2) {
            Text(HealthKitService.workoutActivityTypeDisplayName(workout.activityType))
                .font(.subheadline.bold())
            Text(
                "\(Self.monthDayFormatter.string(from: workout.start)) · \(SleepAnalysisService.formattedDuration(duration)) · " +
                    "\(Self.hourMinuteFormatter.string(from: workout.start)) ~ \(Self.hourMinuteFormatter.string(from: workout.end))"
            )
            .font(.caption2)
            if let energyBurnedKcal = workout.energyBurnedKcal, energyBurnedKcal > 0 {
                Text("\(Int(energyBurnedKcal.rounded()))kcal")
                    .font(.caption2)
            }
            if let distanceMeters = workout.distanceMeters, distanceMeters > 0 {
                Text(String(format: "%.2fkm", distanceMeters / 1000))
                    .font(.caption2)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    // 캘린더 일정이나 수면 막대를 탭하면 뜨는 상세 패널 — lineAndGanttChartsStack의 오버레이로
    // x축 위치에 붙여서 그린다(HRVAnalysisView+Charts.swift). 오버레이라 레이아웃 높이에 영향을
    // 주지 않고, 그 아래 범례 위에 겹쳐서 나온다.
    @ViewBuilder
    var selectedItemDetailPanel: some View {
        if let event = tooltipCalendarEvent {
            tooltipLabel(for: event)
                .overlay(alignment: .topTrailing) {
                    closeButton { tooltipCalendarEvent = nil }
                }
        } else if let sleepRange = tooltipSleepRange {
            SleepDetailPanel(sleepRange: sleepRange) { tooltipSleepRange = nil }
        } else if let workoutRange = tooltipWorkoutRange {
            tooltipLabel(for: workoutRange)
                .overlay(alignment: .topTrailing) {
                    closeButton { tooltipWorkoutRange = nil }
                }
        }
    }

    private func closeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 20))
                .foregroundStyle(.gray)
        }
        .padding(8)
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
                if viewModel.wearableRMSSDMonthlyStats.isEmpty && viewModel.examPoints.isEmpty {
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
                    // 검사·수면·운동 등 다른 데이터는 있는데 rMSSD 계산용 원시 박동 시리즈만 없는 경우가
                    // 있다 (기기/OS/측정 상황에 따라 다름) — 차트가 빈 채로만 나오면 오류처럼 보이므로 안내.
                    if !viewModel.isLoadingHealthKit && currentRMSSDPoints.isEmpty {
                        Text("이 기간에는 rMSSD를 계산할 원시 박동 데이터가 없어요")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    lineAndGanttChartsStack
                }
            }

            if let healthKitErrorMessage = viewModel.healthKitErrorMessage {
                Text(healthKitErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let calendarErrorMessage = viewModel.calendarErrorMessage {
                Text(calendarErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            legend
        }
    }

    // 범례 한 칸. 월별 rMSSD는 박스(1Q~3Q)/심지(최소~최대) 두 칸으로 나뉘지만 둘 다 같은 series를
    // 가리켜서, 탭하면 항상 rMSSD 전체가 같이 토글된다 — 각 칸이 grid의 독립된 셀이라 다른 한 줄짜리
    // 항목과도 자연스럽게 좌측 정렬로 나란히 놓인다(한 칸 안에 두 줄을 욱여넣지 않음).
    private struct LegendItem: Identifiable {
        let id: String
        let series: HRVSeries
        let label: String
        let boldValue: String?
        let swatch: AnyView
    }

    private var legendItems: [LegendItem] {
        HRVSeries.allCases.filter { $0.appliesTo(chartMode) }.flatMap { series -> [LegendItem] in
            if series == .rmssd, chartMode == .monthly {
                // 세 스와치의 실제 그림 크기(8pt/2pt/2pt)가 서로 달라도, 모두 같은 12x14 칸 안에
                // 가운데 정렬해서 스와치 모양과 무관하게 텍스트 세로 위치가 셋 다 나란히 맞는다.
                // 순서는 차트에서 겹쳐 그리는 순서(뒤→앞)와 같다: 심지 → 박스 → 중앙값.
                return [
                    LegendItem(
                        id: "rmssd-line",
                        series: .rmssd,
                        label: "최소~최대",
                        boldValue: nil,
                        swatch: AnyView(
                            Rectangle()
                                .fill(rmssdColor.opacity(0.5))
                                .frame(width: 2, height: 10)
                                .frame(width: 12, height: 14)
                        )
                    ),
                    LegendItem(
                        id: "rmssd-box",
                        series: .rmssd,
                        label: "1Q~3Q",
                        boldValue: nil,
                        swatch: AnyView(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.rmssdRange)
                                .frame(width: 12, height: 8)
                                .frame(width: 12, height: 14)
                        )
                    ),
                    LegendItem(
                        id: "rmssd-median",
                        series: .rmssd,
                        label: "중앙값",
                        boldValue: nil,
                        swatch: AnyView(
                            Rectangle()
                                .fill(rmssdColor)
                                .frame(width: 12, height: 2)
                                .frame(width: 12, height: 14)
                        )
                    )
                ]
            }
            return [
                LegendItem(
                    id: series.id,
                    series: series,
                    label: series.label,
                    boldValue: series == .median ? medianLegendValue : nil,
                    swatch: AnyView(
                        Image(systemName: series.symbol)
                            .font(.system(size: 8))
                            .foregroundStyle(seriesColor(series))
                    )
                )
            ]
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(legendItems) { item in
                Button {
                    toggleSeries(item.series)
                    tooltipCalendarEvent = nil
                    tooltipSleepRange = nil
                    tooltipWorkoutRange = nil
                } label: {
                    legendRow(label: item.label, boldValue: item.boldValue) { item.swatch }
                        .opacity(hiddenSeries.contains(item.series) ? 0.35 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var medianLegendValue: String? {
        guard let median = viewModel.recentThirtyDayRMSSDMedian else { return nil }
        return "\(Int(median.rounded()))ms"
    }

    private func legendRow<Swatch: View>(
        label: String,
        boldValue: String? = nil,
        @ViewBuilder swatch: () -> Swatch
    ) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let boldValue {
                Text(boldValue)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
            }
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
        case .rmssd: rmssdColor
        case .examRmssd: examRmssdColor
        case .sleep: sleepColor
        case .exercise: exerciseColor
        case .median: .gray
        case .sdnn: Theme.systemGray4
        case .calendarEvent: calendarEventColor
        case .cv: Theme.systemTeal
        }
    }
}

#Preview {
    HRVAnalysisView()
        .environment(ToastCenter())
}
