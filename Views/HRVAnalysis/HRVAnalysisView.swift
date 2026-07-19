import Charts
import SwiftUI

private extension HealthKitService.SleepStage {
    var label: String {
        switch self {
        case .deep: "깊은 수면"
        case .rem: "렘(REM)"
        case .core: "코어"
        case .unspecified: "수면(단계 미상)"
        }
    }
}

enum HRVChartMode: String, CaseIterable {
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
        case .monthly: "chart.bar"
        }
    }
}

// 범례에 나오는 지표 단위. 범례를 탭하면 hiddenSeries에 넣고 빼서 차트에서 보이기/숨기기를 토글한다.
enum HRVSeries: String, CaseIterable, Identifiable {
    case rmssd, examRmssd, sleep, exercise, median, sdnn, calendarEvent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rmssd: "rMSSD (계산값)"
        case .examRmssd: "검사 rMSSD"
        case .sleep: "수면"
        case .exercise: "운동"
        case .median: "최근 30일 중앙값"
        case .sdnn: "SDNN (참고용, 시간별)"
        case .calendarEvent: "캘린더"
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
        }
    }
}

struct HRVAnalysisView: View {
    @State var viewModel = HRVAnalysisViewModel()
    @State var chartMode: HRVChartMode = .hourly
    @State var hrvScrollPosition = Date().addingTimeInterval(-HRVChartMode.hourly.visibleDomain)
    @State var dragAnchorPosition: Date?
    @State var hiddenSeries: Set<HRVSeries> = []
    @State var tooltipPoint: HRVAnalysisViewModel.HRVPoint?
    @State var tooltipCalendarEvent: HRVAnalysisViewModel.CalendarEventRange?
    @State var tooltipSleepRange: HRVAnalysisViewModel.SleepRange?
    // 간트 차트는 세로 폭이 좁아 캘린더/수면 툴팁을 그 안에 그리면 잘리므로, x 좌표만 여기 저장해두고
    // lineAndGanttChartsStack 바깥쪽 오버레이(세로 공간이 넉넉함)에서 그 위치에 그린다.
    @State var calendarTooltipAnchorX: CGFloat?
    @State var sleepTooltipAnchorX: CGFloat?

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
                    calendarTooltipAnchorX = nil
                    sleepTooltipAnchorX = nil
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
            await viewModel.loadWearableHRVIfNeeded()
            recomputeRange()
        }
        .task {
            await viewModel.loadCalendarEventsIfNeeded()
        }
        .onChange(of: chartMode) { _, newMode in
            hrvScrollPosition = latestVisibleEnd(for: newMode).addingTimeInterval(-newMode.visibleDomain)
            tooltipPoint = nil
            tooltipCalendarEvent = nil
            tooltipSleepRange = nil
            calendarTooltipAnchorX = nil
            sleepTooltipAnchorX = nil
            recomputeRange()
        }
        .refreshable {
            await viewModel.reload()
            recomputeRange()
        }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        // 라이트 모드에서는 배경이 흰색에 가까워 테두리가 없으면 툴팁이 안 보일 수 있다.
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .fixedSize()
    }

    private func calendarEventTimeRangeText(_ event: HRVAnalysisViewModel.CalendarEventRange) -> String {
        if event.isAllDay {
            return "\(Self.monthDayFormatter.string(from: event.start)) 종일"
        }
        return "\(Self.tooltipDateFormatter.string(from: event.start)) ~ \(Self.hourMinuteFormatter.string(from: event.end))"
    }

    // 단계별로 보여줄 순서 — 중요도가 높은 깊은 수면/렘을 앞에 둔다.
    private static let sleepStageDisplayOrder: [HealthKitService.SleepStage] = [.deep, .rem, .core, .unspecified]

    private func sleepScoreLabel(_ score: Int) -> String {
        switch score {
        case 80...: "좋음"
        case 60..<80: "보통"
        default: "나쁨"
        }
    }

    func tooltipLabel(for sleepRange: HRVAnalysisViewModel.SleepRange) -> some View {
        let totalDuration = sleepRange.end.timeIntervalSince(sleepRange.start)
        let trackedDuration = sleepRange.stageDurations.values.reduce(0, +)
        let awakeDuration = max(0, totalDuration - trackedDuration)

        return VStack(alignment: .leading, spacing: 2) {
            // 애플 Health 앱이 보여주는 수면 점수는 HealthKit으로 못 받아와서, 애플이 공개한 가중치
            // 구성(수면시간+취침 일관성+각성)을 흉내 낸 추정치라는 걸 "추정"으로 명시한다.
            Text("추정 수면 점수 \(sleepRange.estimatedScore)점 · \(sleepScoreLabel(sleepRange.estimatedScore))")
                .font(.subheadline.bold())
            Text(
                "\(formattedDuration(totalDuration)) · \(Self.hourMinuteFormatter.string(from: sleepRange.start)) ~ \(Self.hourMinuteFormatter.string(from: sleepRange.end))"
            )
            .font(.caption2)
            ForEach(Self.sleepStageDisplayOrder, id: \.self) { stage in
                if let duration = sleepRange.stageDurations[stage] {
                    Text("\(stage.label) \(formattedDuration(duration))")
                        .font(.caption2)
                }
            }
            if awakeDuration >= 60 {
                Text("깨어있음 \(formattedDuration(awakeDuration))")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
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
        case .rmssd: rmssdColor
        case .examRmssd: examRmssdColor
        case .sleep: sleepColor
        case .exercise: exerciseColor
        case .median: .gray
        case .sdnn: Theme.systemGray4
        case .calendarEvent: calendarEventColor
        }
    }
}

#Preview {
    HRVAnalysisView()
}
