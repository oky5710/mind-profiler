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

private enum PatternSection: String, CaseIterable, Identifiable {
    case hrv = "HRV"
    case sleep = "수면"

    var id: String { rawValue }
}

// 범례에 나오는 지표 단위. 범례를 탭하면 hiddenSeries에 넣고 빼서 차트에서 보이기/숨기기를 토글한다.
enum HRVSeries: String, CaseIterable, Identifiable {
    case rmssd, examRmssd, restingHeartRate, sleep, daylight, exercise, coffee, medication, symptom, lifeEvent
    case median, sdnn, calendarEvent, cv
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rmssd: "rMSSD (계산값)"
        case .examRmssd: "검사 rMSSD"
        case .restingHeartRate: "안정시 심박수"
        case .sleep: "수면"
        case .daylight: "일광시간"
        case .exercise: "운동"
        case .coffee: "커피"
        case .medication: "약 복용"
        case .symptom: "증상"
        case .lifeEvent: "이벤트"
        case .median: "최근 30일 시간대별 중앙값"
        case .sdnn: "SDNN"
        case .calendarEvent: "캘린더"
        case .cv: "변동계수 (CV)"
        }
    }

    var symbol: String {
        switch self {
        case .rmssd: "circle.fill"
        case .examRmssd: "triangle.fill"
        case .restingHeartRate: "chart.bar.fill"
        case .sleep, .exercise: "square.fill"
        case .daylight: "sun.max.fill"
        case .coffee, .medication: "circle.fill"
        case .symptom: "exclamationmark.circle.fill"
        case .lifeEvent: "star.fill"
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
        case .rmssd, .examRmssd: true
        case .median: mode == .hourly
        case .sdnn: mode == .hourly
        case .restingHeartRate: mode == .daily
        case .sleep: mode != .monthly
        case .daylight: mode == .daily
        case .exercise, .coffee, .medication, .symptom, .lifeEvent, .calendarEvent: mode == .hourly
        case .cv: mode == .monthly
        }
    }
}

struct HRVAnalysisView: View {
    static let maximumRMSSDChartValue = 150.0
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
    @State var tooltipDailyMarker: HRVAnalysisViewModel.DailyMarker?

    // hrvScrollPosition이 스크롤 중 계속 바뀌는데, 매 프레임 body가 다시 계산될 때마다
    // 전체 포인트를 다시 스캔하면 스크롤이 심하게 느려져서 모드/데이터가 바뀔 때만 갱신.
    @State var cachedRange: (min: Double, max: Double) = (0, 100)
    // UIKit(UIScreen) 없이 화면 높이를 구하기 위해 GeometryReader로 실측한다 (AGENTS.md: UIKit 사용 금지).
    // 처음 그려질 때는 아직 측정 전이라 흔한 화면 높이로 잠깐 대체했다가, onAppear에서 바로 갱신된다.
    @State var availableHeight: CGFloat = 850
    // 월별 막대 너비 = bandwidth(월 하나가 차지하는 폭)의 50%, 10~30px로 clamp. 실측 전 기본값.
    @State var monthlyBarWidth: CGFloat = 20
    // 처음 나타날 때는 아래 .task들이 이미 최초 로딩을 하니, onAppear의 강제 재조회는 그 다음
    // 탭 재진입부터만 하면 된다 — 최초 진입에서 두 번 불러오는 낭비를 막는다.
    @State var hasAppearedBefore = false
    @State private var selectedPatternSection: PatternSection = .hrv

    let rmssdColor = Theme.rmssd
    let examRmssdColor = Theme.examRmssd
    let exerciseColor = Theme.exercise
    let sleepColor = Theme.sleep
    let calendarEventColor = Theme.systemBlue

    static let hourMinuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
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

    // 일별 모드의 point.date는 실제 샘플 시각이 아니라 그날 자정(그날의 대표값)이라, 시간 오차로
    // 매칭하면 자정 근처가 아닌 이상 항상 실패한다 — 모드별로 다른 매칭 기준을 쓴다.
    func matchedRMSSDEvent(for date: Date) -> RMSSDEventEntry? {
        switch chartMode {
        case .hourly: viewModel.rmssdEvent(near: date)
        case .daily: viewModel.rmssdEvent(onDay: date)
        case .monthly: nil
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

    // 시간별 모드에서만 쓰는 전체 예약 높이 — 실제 막대(수면/운동/캘린더) 차트가 이 중 2/3를,
    // 그 아래 새 아이콘 레인(커피/약복용/이벤트)이 나머지 1/3을 차지한다. 이 값 자체는 그대로 둬서
    // (라인 차트 + 이 값)을 바닥 기준으로 삼는 selectedItemDetailPanel의 오프셋 계산이 안 바뀐다.
    var ganttChartHeight: CGFloat {
        lineChartHeight / 2 * 0.7
    }

    var ganttBarsHeight: CGFloat {
        ganttChartHeight * 2 / 3
    }

    var iconLaneHeight: CGFloat {
        ganttChartHeight - ganttBarsHeight
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
            VStack(spacing: 0) {
                Picker("분석 종류", selection: $selectedPatternSection) {
                    ForEach(PatternSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)

                if selectedPatternSection == .hrv {
                    GeometryReader { geo in
                // .refreshable(아래 배치)은 ScrollView/List 같은 실제 스크롤 가능한 조상이 있어야
                // 당겨서 새로고침 제스처를 인식한다 — VStack만 있던 예전 구조에선 아래로 당겨도
                // 아무 반응이 없었다.
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hrvChart
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom)
                    .frame(minHeight: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 차트 자체는 자기 드래그 제스처가 우선 처리하므로, 여기는 차트 바깥(빈 영역)을
                        // 탭했을 때만 걸린다.
                        tooltipPoint = nil
                        tooltipCalendarEvent = nil
                        tooltipSleepRange = nil
                        tooltipWorkoutRange = nil
                        tooltipDailyMarker = nil
                    }
                }
                .onAppear { availableHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, newHeight in availableHeight = newHeight }
                    }
                } else {
                    SleepOverviewView()
                }
            }
            .navigationTitle("오늘의 패턴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("오늘의 패턴").font(Typography.screenTitle)
                }
            }
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
            recomputeRange()
        }
        .task {
            await viewModel.loadCalendarEventsIfNeeded()
        }
        .task {
            await viewModel.loadRMSSDEventsIfNeeded()
        }
        .task {
            await viewModel.loadDailyMarkersIfNeeded()
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
            tooltipDailyMarker = nil
            recomputeRange()
        }
        .refreshable {
            await viewModel.reload()
            // 지금 보이는 구간은 pull-to-refresh니까 이미 로드돼 있어도(force) 무조건 다시 불러온다 —
            // 워치에서 새로 동기화된 데이터가 있을 수 있어서다.
            await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd, force: true)
            await viewModel.loadCalendarEventsIfNeeded()
            await viewModel.reloadRMSSDEvents()
            await viewModel.reloadDailyMarkers()
            recomputeRange()
        }
        // 탭을 나갔다가 다시 들어올 때마다 pull-to-refresh와 같은 강제 새로고침을 한다 — 캘린더에서
        // 운동/이벤트를 새로 입력하고 이 탭으로 돌아와도 예전에 로드해둔 값을 그대로 보여주던 문제.
        .onAppear {
            guard hasAppearedBefore else {
                hasAppearedBefore = true
                return
            }
            Task {
                await viewModel.reload()
                await viewModel.ensureHealthKitDataLoaded(visibleStart: visibleStart, visibleEnd: visibleEnd, force: true)
                await viewModel.loadCalendarEventsIfNeeded()
                await viewModel.reloadRMSSDEvents()
                await viewModel.reloadDailyMarkers()
                recomputeRange()
            }
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
            if let median = viewModel.recentThirtyDayRMSSDMedian { values.append(median) }
            values += viewModel.recentThirtyDayPeriodMedians?.values ?? []
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
                Text("HRV Trend").font(Typography.sectionTitle)
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
            .padding(.bottom, 16)

            hrvChartBody
        }
    }

    // SDNN은 시간별 모드에서만 그려지므로(hiddenSeries로 꺼져 있어도 마찬가지) 그 외에는 nil —
    // 툴팁이 찾는 rMSSD 포인트와 정확히 같은 시각의 샘플이 없을 수 있어 가장 가까운 값을 쓴다.
    private func nearestSDNNValue(to date: Date) -> Double? {
        guard chartMode == .hourly, !hiddenSeries.contains(.sdnn) else { return nil }
        return viewModel.wearableSDNNPointsHourly.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.value
    }

    private func dailyRestingHeartRate(on date: Date) -> Double? {
        guard chartMode == .daily else { return nil }
        return viewModel.wearableRestingHeartRatePointsDaily.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }?.value
    }

    private func dailySleepDuration(on date: Date) -> TimeInterval? {
        guard chartMode == .daily else { return nil }
        return viewModel.nightlySleepPointsDaily.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }.map { $0.hours * 3_600 }
    }

    func tooltipLabel(for point: HRVAnalysisViewModel.HRVPoint) -> some View {
        // 일별 모드는 하루 대표값(중앙값)이라 시각을 붙이면 의미 없는 00:00 같은 값이 나온다.
        let dateText = chartMode == .daily
            ? Self.monthDayFormatter.string(from: point.date)
            : Self.tooltipDateFormatter.string(from: point.date)
        let matchedEvent = matchedRMSSDEvent(for: point.date)

        return VStack(alignment: .leading, spacing: 2) {
            Text(dateText)
                .font(.caption2)
            // 라벨(rMSSD/SDNN)은 작게, 숫자는 크게 — Grid로 두 줄의 라벨 칸 너비를 맞춰서
            // 숫자가 시작하는 위치가 항상 같은 줄에 맞게 정렬된다. 기분은 rMSSD/SDNN처럼 측정값이
            // 아니라 사용자가 고른 짧은 단어라 굳이 크게 강조하지 않고 라벨과 같은 작은 크기로 둔다.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 4, verticalSpacing: 2) {
                GridRow {
                    Text("rMSSD").font(.caption2)
                    Text("\(String(format: "%.0f", point.value))ms").font(.callout.bold())
                }
                if let sdnn = nearestSDNNValue(to: point.date) {
                    GridRow {
                        Text("SDNN").font(.caption2)
                        Text("\(String(format: "%.0f", sdnn))ms").font(.callout.bold())
                    }
                }
                if let restingHeartRate = dailyRestingHeartRate(on: point.date) {
                    GridRow {
                        Text("안정시 심박수").font(.caption2)
                        Text("\(String(format: "%.0f", restingHeartRate))bpm").font(.callout.bold())
                    }
                }
                if let sleepDuration = dailySleepDuration(on: point.date) {
                    GridRow {
                        Text("수면시간").font(.caption2)
                        Text(SleepAnalysisService.formattedDuration(sleepDuration)).font(.callout.bold())
                    }
                }
                if let emotion = matchedEvent.flatMap({ RMSSDEmotion(rawValue: $0.emotion) }) {
                    GridRow {
                        Text("기분").font(.caption2)
                        Text(emotion.label).font(.caption2)
                    }
                }
            }
            if let note = matchedEvent?.note, !note.isEmpty {
                // 메모는 입력 폼에서 글자 수 제한이 없어서, 다른 줄처럼 fixedSize에 맡기면(한 줄
                // 통짜 너비를 그대로 요구) 툴팁이 화면 밖으로 넘어갈 만큼 넓어질 수 있다 — 너비를
                // 직접 제한하고 세로로만 줄바꿈되게 한다.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
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
            Text(workout.displayName)
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
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
        } else if let marker = tooltipDailyMarker {
            tooltipLabel(for: marker)
                .overlay(alignment: .topTrailing) {
                    closeButton { tooltipDailyMarker = nil }
                }
        }
    }

    private static let dailyMarkerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private func dailyMarkerKindLabel(_ kind: HRVAnalysisViewModel.DailyMarkerKind) -> String {
        switch kind {
        case .coffee: "커피"
        case .medication: "약 복용"
        case .symptom: "증상"
        case .event: "이벤트"
        }
    }

    func tooltipLabel(for marker: HRVAnalysisViewModel.DailyMarker) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dailyMarkerKindLabel(marker.kind))
                .font(.caption2.bold())
                .foregroundStyle(dailyMarkerColor(for: marker.kind))
            // 약복용은 제목이 종류 라벨("약 복용")과 똑같아서 — 약 이름 자체는 원래 안 보여주는
            // 정책이라(DayDetailSheet와 동일) 중복으로 한 번 더 보여줄 필요가 없다.
            if marker.kind != .medication {
                Text(marker.title)
                    .font(.subheadline.bold())
            }
            if let intensity = marker.intensity {
                Text("강도 \(intensity)")
                    .font(.caption2.bold())
            }
            if let description = marker.description, !description.isEmpty {
                Text(description)
                    .font(.caption2)
            }
            Text(Self.dailyMarkerTimeFormatter.string(from: marker.date))
                .font(.caption2)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
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

            // 이 VStack의 기본 spacing(8)에 18을 더해 차트와 범례 사이만 26pt로 띄운다.
            legend
                .padding(.top, 18)
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
                    label: series == .sleep && chartMode == .daily ? "야간 수면시간" : series.label,
                    boldValue: legendValue(for: series),
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
        let items = legendItems
        let regularItems = items.filter { $0.series != .median }
        let medianItem = items.first { $0.series == .median }

        return VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(regularItems) { item in
                    legendButton(item)
                }
            }

            if let medianItem {
                legendButton(medianItem)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private func legendButton(_ item: LegendItem) -> some View {
        Button {
            toggleSeries(item.series)
            tooltipCalendarEvent = nil
            tooltipSleepRange = nil
            tooltipWorkoutRange = nil
        } label: {
            if item.series == .median {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        item.swatch
                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let value = item.boldValue {
                        Text(value)
                            .font(.caption2.bold())
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(hiddenSeries.contains(item.series) ? 0.35 : 1)
            } else {
                legendRow(label: item.label, boldValue: item.boldValue) { item.swatch }
                    .opacity(hiddenSeries.contains(item.series) ? 0.35 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func legendValue(for series: HRVSeries) -> String? {
        switch series {
        case .median:
            guard let values = viewModel.recentThirtyDayPeriodMedians else { return nil }
            let morning = values.morning.map { "오전 \(Int($0.rounded()))" }
            let afternoon = values.afternoon.map { "오후 \(Int($0.rounded()))" }
            let sleep = values.sleep.map { "수면 \(Int($0.rounded()))" }
            return [morning, afternoon, sleep].compactMap { $0 }.joined(separator: " · ") + "ms"
        default:
            return nil
        }
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
        case .restingHeartRate: Theme.systemMint
        case .sleep: sleepColor
        case .daylight: Theme.systemYellow
        case .exercise: exerciseColor
        case .coffee: Theme.hourlyCoffeeMarker
        case .medication: Theme.hourlyMedicationMarker
        case .symptom: Theme.systemRed
        case .lifeEvent: calendarEventColor
        case .median: sleepColor
        case .sdnn: Theme.systemGray4
        case .calendarEvent: calendarEventColor
        case .cv: Theme.systemTeal
        }
    }
}

@MainActor
@Observable
private final class SleepOverviewViewModel {
    struct TimelineSegment: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let stage: HealthKitService.SleepTimelineStage
    }

    struct MetricPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private(set) var selectedNight = Calendar.current.date(
        byAdding: .day,
        value: -1,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()
    private(set) var timeline: [TimelineSegment] = []
    private(set) var rmssdPoints: [MetricPoint] = []
    private(set) var heartRatePoints: [MetricPoint] = []
    private(set) var respiratoryRatePoints: [MetricPoint] = []
    private(set) var rmssdThirtyDayAverage: Double?
    private(set) var dailyRestingHeartRate: Double?
    private(set) var continuityBaseline: SleepContinuityBaseline?
    private(set) var sleepRange: SleepRange?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var chartDomain: ClosedRange<Date> {
        if let sleepRange, sleepRange.end > sleepRange.start {
            let start = sleepRange.start.addingTimeInterval(-30 * 60)
            let end = sleepRange.end.addingTimeInterval(30 * 60)
            return start...end
        }
        let start = fallbackDomain.lowerBound.addingTimeInterval(-30 * 60)
        let end = fallbackDomain.upperBound.addingTimeInterval(30 * 60)
        return start...end
    }

    private var fallbackDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedNight) ?? selectedNight
        let end = calendar.date(byAdding: .hour, value: 18, to: start) ?? start.addingTimeInterval(18 * 60 * 60)
        return start...end
    }

    var totalSleepDuration: TimeInterval? {
        sleepRange.map { $0.stageDurations.values.reduce(0, +) }
    }

    var sleepRMSSDAverage: Double? {
        guard !rmssdPoints.isEmpty else { return nil }
        return rmssdPoints.map(\.value).reduce(0, +) / Double(rmssdPoints.count)
    }

    var currentContinuityMetrics: SleepContinuityMetrics {
        guard let sleepRange else {
            return SleepContinuityMetrics(
                totalAwakeDuration: 0,
                awakeningCount: 0,
                longestAwakening: 0,
                longestContinuousSleep: 0,
                sleepWindowDuration: 0
            )
        }
        return Self.makeContinuityMetrics(
            ranges: [sleepRange],
            timeline: timeline.map { ($0.start, $0.end, $0.stage) }
        )
    }

    var heartRateDomain: ClosedRange<Double> {
        var values = heartRatePoints.map(\.value)
        if let dailyRestingHeartRate {
            values.append(dailyRestingHeartRate)
        }
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }
        guard minimum < maximum else {
            return (minimum - 1)...(maximum + 1)
        }
        return minimum...maximum
    }

    func moveDay(by value: Int) async {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: value, to: selectedNight) else { return }
        let latest = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
        guard next <= latest else { return }
        selectedNight = next
        await load()
    }

    func selectNight(_ date: Date) async {
        let calendar = Calendar.current
        let selected = calendar.startOfDay(for: date)
        let latest = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
        guard selected <= latest else { return }
        selectedNight = selected
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await HealthKitService.requestAuthorization()
            let calendar = Calendar.current
            let searchDomain = fallbackDomain
            let contextStart = calendar.date(byAdding: .day, value: -30, to: selectedNight)
                ?? searchDomain.lowerBound

            let sleepSamples = try await HealthKitService.fetchSleepStageSamples(
                start: contextStart,
                end: searchDomain.upperBound
            )
            sleepRange = SleepAnalysisService.buildSleepRanges(sleepSamples).last {
                calendar.isDate(SleepAnalysisService.nightLabel(for: $0.start), inSameDayAs: selectedNight)
            }

            guard let sleepRange else {
                timeline = []
                rmssdPoints = []
                heartRatePoints = []
                respiratoryRatePoints = []
                dailyRestingHeartRate = nil
                continuityBaseline = nil
                return
            }

            let domain = sleepRange.start...sleepRange.end
            async let timelineTask = HealthKitService.fetchSleepTimelineSamples(start: domain.lowerBound, end: domain.upperBound)
            async let rmssdTask = HealthKitService.fetchRMSSDSamples(start: domain.lowerBound, end: domain.upperBound)
            async let heartRateTask = HealthKitService.fetchHeartRateSamples(start: domain.lowerBound, end: domain.upperBound)
            async let respiratoryTask = HealthKitService.fetchRespiratoryRateSamples(start: domain.lowerBound, end: domain.upperBound)
            // 수면은 취침일로 표시하지만 HealthKit 안정시 심박수는 보통 기상일에 기록된다.
            let wakeDayStart = calendar.startOfDay(for: sleepRange.end)
            let wakeDayEnd = calendar.date(byAdding: .day, value: 1, to: wakeDayStart)
                ?? wakeDayStart.addingTimeInterval(24 * 60 * 60)
            async let restingHeartRateTask = HealthKitService.fetchRestingHeartRateSamples(
                start: wakeDayStart,
                end: wakeDayEnd
            )
            async let thirtyDayTimelineTask = HealthKitService.fetchSleepTimelineSamples(
                start: contextStart,
                end: searchDomain.upperBound
            )
            let (rawTimeline, rmssd, heartRate, respiratoryRate, restingHeartRates, thirtyDayTimeline) = try await (
                timelineTask,
                rmssdTask,
                heartRateTask,
                respiratoryTask,
                restingHeartRateTask,
                thirtyDayTimelineTask
            )
            timeline = rawTimeline.map {
                TimelineSegment(
                    start: max($0.start, domain.lowerBound),
                    end: min($0.end, domain.upperBound),
                    stage: $0.stage
                )
            }
            rmssdPoints = rmssd.map { MetricPoint(date: $0.date, value: $0.value) }
            heartRatePoints = heartRate.map { MetricPoint(date: $0.date, value: $0.value) }
            respiratoryRatePoints = respiratoryRate.map { MetricPoint(date: $0.date, value: $0.value) }
            dailyRestingHeartRate = restingHeartRates.isEmpty
                ? nil
                : restingHeartRates.map(\.value).reduce(0, +) / Double(restingHeartRates.count)
            continuityBaseline = Self.makeContinuityBaseline(
                ranges: SleepAnalysisService.buildSleepRanges(sleepSamples),
                timeline: thirtyDayTimeline,
                from: calendar.startOfDay(for: contextStart),
                through: selectedNight
            )

            if rmssdThirtyDayAverage == nil {
                let averageEnd = Date()
                let averageStart = calendar.date(byAdding: .day, value: -30, to: averageEnd) ?? averageEnd
                let recentRMSSD = try await HealthKitService.fetchRMSSDSamples(start: averageStart, end: averageEnd)
                if !recentRMSSD.isEmpty {
                    rmssdThirtyDayAverage = recentRMSSD.map(\.value).reduce(0, +) / Double(recentRMSSD.count)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func makeContinuityBaseline(
        ranges: [SleepRange],
        timeline: [(start: Date, end: Date, stage: HealthKitService.SleepTimelineStage)],
        from startNight: Date,
        through endNight: Date
    ) -> SleepContinuityBaseline? {
        let eligibleRanges = ranges.filter {
            let night = SleepAnalysisService.nightLabel(for: $0.start)
            return night >= startNight && night < endNight
        }
        let rangesByNight = Dictionary(grouping: eligibleRanges) {
            SleepAnalysisService.nightLabel(for: $0.start)
        }
        let nights = rangesByNight.values.map {
            makeContinuityMetrics(ranges: $0, timeline: timeline)
        }
        return makeSleepContinuityBaseline(from: nights)
    }

    private static func makeContinuityMetrics(
        ranges: [SleepRange],
        timeline: [(start: Date, end: Date, stage: HealthKitService.SleepTimelineStage)]
    ) -> SleepContinuityMetrics {
        var totalAwakeDuration: TimeInterval = 0
        var awakeningCount = 0
        var longestAwakening: TimeInterval = 0
        var longestContinuousSleep: TimeInterval = 0
        var sleepWindowDuration: TimeInterval = 0

        for range in ranges {
            sleepWindowDuration += max(0, range.end.timeIntervalSince(range.start))
            let mergedAwake = SleepAnalysisService.awakeIntervals(within: range, timeline: timeline)
            let awakeDurations = mergedAwake.map { $0.end.timeIntervalSince($0.start) }
            totalAwakeDuration += awakeDurations.reduce(0, +)
            awakeningCount += awakeDurations.filter { $0 >= 60 }.count
            longestAwakening = max(longestAwakening, awakeDurations.max() ?? 0)

            var cursor = range.start
            for awake in mergedAwake {
                longestContinuousSleep = max(
                    longestContinuousSleep,
                    max(0, awake.start.timeIntervalSince(cursor))
                )
                cursor = max(cursor, awake.end)
            }
            longestContinuousSleep = max(
                longestContinuousSleep,
                max(0, range.end.timeIntervalSince(cursor))
            )
        }

        return SleepContinuityMetrics(
            totalAwakeDuration: totalAwakeDuration,
            awakeningCount: awakeningCount,
            longestAwakening: longestAwakening,
            longestContinuousSleep: longestContinuousSleep,
            sleepWindowDuration: sleepWindowDuration
        )
    }

}

private struct SleepOverviewView: View {
    @State private var viewModel = SleepOverviewViewModel()
    @State private var selectedRMSSDDate: Date?
    @State private var selectedHeartRateDate: Date?
    @State private var showsDatePicker = false
    @State private var pendingNight = Calendar.current.startOfDay(for: Date())

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 EEEE"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let tooltipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                summary

                if viewModel.isLoading && viewModel.timeline.isEmpty {
                    ProgressView("수면 데이터를 불러오는 중...")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage = viewModel.errorMessage, viewModel.timeline.isEmpty {
                    ContentUnavailableView(
                        "수면 데이터를 불러올 수 없어요",
                        systemImage: "bed.double",
                        description: Text(errorMessage)
                    )
                    .frame(minHeight: 260)
                } else if viewModel.sleepRange == nil {
                    ContentUnavailableView(
                        "수면 기록이 없어요",
                        systemImage: "bed.double",
                        description: Text("좌우로 스와이프해 다른 날짜를 확인해 보세요.")
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        continuitySummaryCard
                        VStack(spacing: 0) {
                            sleepStageChart
                            rmssdChart
                            heartRateChart
                            respiratoryRateChart
                        }
                        .padding(.top, 20)
                        .sleepConnectedTimeGrid(domain: viewModel.chartDomain)
                    }
                }
            }
            .padding()
        }
        .refreshable { await viewModel.load() }
        .simultaneousGesture(daySwipeGesture)
        .task { await viewModel.load() }
        .sheet(isPresented: $showsDatePicker) {
            sleepDatePickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var summary: some View {
        let metrics = viewModel.currentContinuityMetrics
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Self.dateFormatter.string(from: viewModel.selectedNight))
                    .font(Typography.sleepDate)
                Spacer()
                Button {
                    pendingNight = viewModel.selectedNight
                    showsDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("수면 날짜 선택")
            }
            .padding(.vertical, 2)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 2),
                spacing: 8
            ) {
                wakeMetric(
                    "총 수면 시간",
                    value: viewModel.totalSleepDuration.map { Self.formattedDuration($0) } ?? "—"
                )
                wakeMetric(
                    "가장 긴 연속 수면",
                    value: Self.formattedDuration(metrics.longestContinuousSleep)
                )
                wakeMetric("총 각성 시간", value: Self.formattedDuration(metrics.totalAwakeDuration))
                wakeMetric(
                    "수면 중 rMSSD 평균",
                    value: viewModel.sleepRMSSDAverage.map { "\(Int($0.rounded()))ms" } ?? "—"
                )
            }
        }
    }

    private var sleepDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "수면 날짜",
                selection: $pendingNight,
                in: ...latestSelectableNight,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .padding()
            .navigationTitle("날짜 선택")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pendingNight) { _, newDate in
                showsDatePicker = false
                Task { await viewModel.selectNight(newDate) }
            }
        }
    }

    private var latestSelectableNight: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var continuitySummary: SleepContinuitySummary {
        SleepContinuitySummaryBuilder.build(
            current: viewModel.currentContinuityMetrics,
            baseline: viewModel.continuityBaseline
        )
    }

    private var continuitySummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(continuitySummary.title)
                .font(Typography.cardTitle)
            Text(continuitySummary.detail)
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.primary50)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private static func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours == 0 ? "\(minutes)분" : "\(hours)시간 \(minutes)분"
    }

    private func wakeMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Typography.cardTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 4))
    }

    private var sleepStageChart: some View {
        VStack(spacing: 0) {
            Chart(viewModel.timeline) { segment in
                RectangleMark(
                    xStart: .value("시작", segment.start),
                    xEnd: .value("끝", segment.end),
                    yStart: .value("단계 시작", stageYRange(segment.stage).lowerBound),
                    yEnd: .value("단계 끝", stageYRange(segment.stage).upperBound)
                )
                .foregroundStyle(stageColor(segment.stage))
                .cornerRadius(3)
            }
            .chartXScale(domain: viewModel.chartDomain)
            .chartYScale(domain: 0...4)
            .sleepTimeGrid()
            .chartYAxis(.hidden)
            .sleepStageLabels()
            .sleepXAxisBaseline()
        }
        .frame(height: 154)
    }

    private var rmssdChart: some View {
        metricChart {
            Chart {
                ForEach(viewModel.rmssdPoints) { point in
                    LineMark(x: .value("시간", point.date), y: .value("rMSSD", point.value))
                        .foregroundStyle(Theme.rmssd)
                    PointMark(x: .value("시간", point.date), y: .value("rMSSD", point.value))
                        .symbol {
                            Circle()
                                .fill(.white)
                                .stroke(Theme.rmssd, lineWidth: 2)
                                .frame(width: 7, height: 7)
                        }
                }
                if let selectedRMSSDPoint {
                    PointMark(
                        x: .value("선택 시간", selectedRMSSDPoint.date),
                        y: .value("선택 rMSSD", selectedRMSSDPoint.value)
                    )
                    .symbol {
                        Circle()
                            .fill(.white)
                            .stroke(Theme.rmssd, lineWidth: 2)
                            .frame(width: 7, height: 7)
                    }
                }
                if let average = viewModel.rmssdThirtyDayAverage {
                    RuleMark(y: .value("최근 30일 평균", average))
                        .foregroundStyle(Theme.systemGray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXScale(domain: viewModel.chartDomain)
            .sleepTimeGrid()
            .chartYAxis(.hidden)
            .sleepMetricLabel("rMSSD")
            .sleepXAxisBaseline()
            .sleepPointTapSelection(
                points: viewModel.rmssdPoints,
                selection: $selectedRMSSDDate
            )
            .sleepValueTooltip(
                point: selectedRMSSDPoint,
                time: selectedRMSSDPoint.map { Self.tooltipTimeFormatter.string(from: $0.date) },
                value: selectedRMSSDPoint.map { String(format: "%.1f ms", $0.value) }
            )
        }
    }

    private var selectedRMSSDPoint: SleepOverviewViewModel.MetricPoint? {
        guard let selectedRMSSDDate else { return nil }
        return viewModel.rmssdPoints.min {
            abs($0.date.timeIntervalSince(selectedRMSSDDate))
                < abs($1.date.timeIntervalSince(selectedRMSSDDate))
        }
    }

    private var heartRateChart: some View {
        metricChart {
            Chart {
                ForEach(viewModel.heartRatePoints) { point in
                    LineMark(
                        x: .value("시간", point.date),
                        y: .value("심박수", point.value)
                    )
                    .foregroundStyle(Theme.heart)

                    if selectedHeartRatePoint?.id == point.id {
                        PointMark(
                            x: .value("선택 시간", point.date),
                            y: .value("선택 심박수", point.value)
                        )
                        .foregroundStyle(Theme.heart)
                        .symbolSize(36)
                    }
                }
                if let restingHeartRate = viewModel.dailyRestingHeartRate {
                    RuleMark(y: .value("안정시 심박수", restingHeartRate))
                        .foregroundStyle(Theme.systemGray)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXScale(domain: viewModel.chartDomain)
            .chartYScale(domain: viewModel.heartRateDomain)
            .sleepTimeGrid()
            .chartYAxis(.hidden)
            .sleepMetricLabel("심박수")
            .sleepXAxisBaseline()
            .sleepPointTapSelection(
                points: viewModel.heartRatePoints,
                selection: $selectedHeartRateDate
            )
            .sleepValueTooltip(
                point: selectedHeartRatePoint,
                time: selectedHeartRatePoint.map { Self.tooltipTimeFormatter.string(from: $0.date) },
                value: selectedHeartRatePoint.map { String(format: "%.0f bpm", $0.value) }
            )
        }
    }

    private var selectedHeartRatePoint: SleepOverviewViewModel.MetricPoint? {
        guard let selectedHeartRateDate else { return nil }
        return viewModel.heartRatePoints.min {
            abs($0.date.timeIntervalSince(selectedHeartRateDate))
                < abs($1.date.timeIntervalSince(selectedHeartRateDate))
        }
    }

    private var respiratoryRateChart: some View {
        metricChart {
            Chart(viewModel.respiratoryRatePoints) { point in
                LineMark(
                    x: .value("시간", point.date),
                    y: .value("호흡수", point.value)
                )
                .foregroundStyle(Theme.systemTeal)
            }
            .chartXScale(domain: viewModel.chartDomain)
            .sleepTimeGrid()
            .chartYAxis(.hidden)
            .sleepMetricLabel("호흡수")
            .sleepXAxisBaseline()
        }
    }

    private func metricChart<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 65)
    }

    private func stageColor(_ stage: HealthKitService.SleepTimelineStage) -> Color {
        switch stage {
        case .deep: Theme.sleepStageDeep
        case .core: Theme.sleepTimelineCore
        case .rem: Theme.sleepStageREM
        case .awake: Theme.sleepTimelineAwake
        }
    }

    private func stageYRange(
        _ stage: HealthKitService.SleepTimelineStage
    ) -> ClosedRange<Double> {
        switch stage {
        case .deep: 3.08...3.92
        case .core: 2.08...2.92
        case .rem: 1.08...1.92
        case .awake: 0.08...0.92
        }
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 60 else { return }
                Task {
                    await viewModel.moveDay(by: value.translation.width < 0 ? 1 : -1)
                }
            }
    }
}

private extension View {
    func sleepStageLabels() -> some View {
        chartPlotStyle { plotArea in
            plotArea.overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { index in
                            Path { path in
                                let y = geometry.size.height * CGFloat(index) / 4
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                            .stroke(Theme.systemGray4.opacity(0.65), lineWidth: 0.6)
                        }

                        VStack(spacing: 0) {
                            ForEach(["깊은 수면", "코어 수면", "REM 수면", "비수면"], id: \.self) { label in
                                Text(label)
                                    .font(Typography.sleepStageLabel)
                                    .foregroundStyle(Theme.systemGray)
                                    .padding(.leading, 6)
                                    .padding(.top, 6)
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topLeading
                                    )
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    func sleepMetricLabel(_ label: String) -> some View {
        chartPlotStyle { plotArea in
            plotArea.overlay(alignment: .topLeading) {
                Text(label)
                    .font(Typography.sleepStageLabel)
                    .foregroundStyle(Theme.systemGray)
                    .fixedSize()
                    .padding(.leading, 6)
                    .padding(.top, 0)
                    .allowsHitTesting(false)
            }
        }
    }

    func sleepValueTooltip(
        point: SleepOverviewViewModel.MetricPoint?,
        time: String?,
        value: String?
    ) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                if let point,
                   let time,
                   let value,
                   let plotFrame = proxy.plotFrame,
                   let x = proxy.position(forX: point.date),
                   let y = proxy.position(forY: point.value) {
                    let frame = geometry[plotFrame]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(time)
                        Text(value)
                            .fontWeight(.semibold)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                    .position(
                        x: min(max(frame.minX + x, frame.minX + 38), frame.maxX - 38),
                        y: max(frame.minY + 20, frame.minY + y - 28)
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    func sleepPointTapSelection(
        points: [SleepOverviewViewModel.MetricPoint],
        selection: Binding<Date?>
    ) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard let plotFrame = proxy.plotFrame else {
                                selection.wrappedValue = nil
                                return
                            }
                            let frame = geometry[plotFrame]
                            guard frame.contains(value.location) else {
                                selection.wrappedValue = nil
                                return
                            }

                            let closest = points.compactMap { point -> (Date, CGFloat)? in
                                guard let x = proxy.position(forX: point.date),
                                      let y = proxy.position(forY: point.value) else { return nil }
                                let pointLocation = CGPoint(x: frame.minX + x, y: frame.minY + y)
                                return (point.date, hypot(
                                    pointLocation.x - value.location.x,
                                    pointLocation.y - value.location.y
                                ))
                            }
                            .min { $0.1 < $1.1 }

                            selection.wrappedValue = closest.map { $0.1 <= 24 ? $0.0 : nil } ?? nil
                        }
                    )
            }
        }
    }

    func sleepTimeGrid() -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Theme.systemGray4.opacity(0.65))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text("\(Calendar.current.component(.hour, from: date))")
                            .font(Typography.chartAxisLabel)
                    }
                }
            }
        }
    }

    func sleepConnectedTimeGrid(domain: ClosedRange<Date>) -> some View {
        background {
            GeometryReader { geometry in
                let duration = domain.upperBound.timeIntervalSince(domain.lowerBound)

                Path { path in
                    guard duration > 0 else { return }
                    for date in sleepHourMarks(in: domain) {
                        let ratio = date.timeIntervalSince(domain.lowerBound) / duration
                        let x = geometry.size.width * ratio
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                }
                .stroke(Theme.systemGray4.opacity(0.65), lineWidth: 0.6)
            }
            .allowsHitTesting(false)
        }
    }

    func sleepXAxisBaseline() -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]

                    Path { path in
                        path.move(to: CGPoint(x: frame.minX, y: frame.maxY))
                        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
                    }
                    .stroke(Theme.systemGray, lineWidth: 1.2)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func sleepHourMarks(in domain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        guard var date = calendar.dateInterval(of: .hour, for: domain.lowerBound)?.end else { return [] }
        var dates: [Date] = []
        while date < domain.upperBound {
            dates.append(date)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }
}

#Preview {
    HRVAnalysisView()
        .environment(ToastCenter())
}
