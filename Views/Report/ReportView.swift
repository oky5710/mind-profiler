import Charts
import SwiftUI

struct ReportView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = ReportViewModel()
    @State private var selectedSleepRange: SleepRange?
    @State private var selectedCVDailyPoint: ReportViewModel.CVDailyPoint?
    @State private var selectedHourPatternPoint: ReportViewModel.HourOfDayPoint?
    // 오늘의 패턴 Gantt 차트와 같은 방식(고정 픽셀 너비)으로 선택 그림자를 그리려고 실측한다.
    @State private var sleepBarWidth: CGFloat = 20

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let weekdaySymbols = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    // ui-style.md "날짜 표기" 규칙 — 인접 포인트 간격이 하루 이상 30일 미만이면 MM-dd 표기.
    // 이 화면의 차트는 항상 날짜 단위(하루 간격) 데이터라 이 축약 규칙 하나만 해당한다.
    // 포맷 자체는 HRVAnalysisView.monthDayFormatter를 그대로 재사용해 앱 전체에서 동일하게 유지한다.
    // ui-style.md "그리드 라인은 옅게, 눈금 틱은 그보다 진하게" — HRVAnalysisView와 같은 값
    // (그리드 .gray.opacity(0.25), 틱 .gray.opacity(0.85))을 유지하되 x축 라벨은 보고서에서
    // 더 잘 보이도록 불투명한 primary 10pt로 표시한다.
    @AxisMarkBuilder
    private static func dateAxisMarks(_ value: AxisValue) -> some AxisMark {
        AxisGridLine().foregroundStyle(.gray.opacity(0.25))
        AxisTick().foregroundStyle(.gray.opacity(0.85))
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(HRVAnalysisView.monthDayFormatter.string(from: date))
                    .font(Typography.chartAxisLabel)
                    .tracking(1)
                    .foregroundStyle(.primary)
            }
        }
    }

    // viewModel.previousVisitDate/thisVisitDate는 DatePicker로 고른 "그날"을 나타낼 뿐인데, 실제
    // Date 값에는 화면을 처음 연 시각의 시(時)·분(分)이 그대로 남아 있다(ReportViewModel.init의
    // `now`). 이 원시 값을 그대로 domain으로 쓰면 첫날/마지막 날의 day-unit 막대·포인트가 자정
    // 기준 하루 전체가 아니라 그 시각부터/까지만 걸쳐 있는 것으로 계산되어, 두 차트 모두 한쪽으로
    // 치우쳐 보인다 — 날짜의 자정(0시)~다음 날 자정으로 정규화한 뒤 써야 한다.
    private var chartDateDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: viewModel.previousVisitDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: viewModel.thisVisitDate)) ?? viewModel.thisVisitDate
        return start...end
    }

    // 수면/CV 차트가 같은 domain을 쓰더라도 각자 자동(automatic) 눈금에 맡기면 마크 종류(Bar vs
    // Area+Line)에 따라 서로 다른 위치에 눈금이 생길 수 있다(ui-style.md "x축 눈금 위치는 반드시
    // 동일해야 한다") — 두 차트가 공유하는 눈금 Date 배열을 직접 계산해서 .chartXAxis에 동일하게 적용한다.
    private var dateAxisTickDates: [Date] {
        let calendar = Calendar.current
        let start = chartDateDomain.lowerBound
        let end = chartDateDomain.upperBound
        guard start < end else { return [start] }

        let totalDays = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let strideDays = max(totalDays / 6, 1)

        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: strideDays, to: current) else { break }
            current = next
        }
        return dates
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 패널(섹션) 사이 위아래 간격을 기간 요약 카드 3개의 가로 간격(12pt)과 통일한다.
                VStack(alignment: .leading, spacing: 12) {
                    datePickers

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Typography.caption)
                            .foregroundStyle(.red)
                    }

                    if viewModel.hasAnalyzed {
                        vitalsSection
                        sleepSection
                        cvSection
                        hourlyPatternSection
                        rmssdLowestFindingsSection
                        rmssdLowestDaysTableSection
                    } else if viewModel.isAnalyzing {
                        HeartLoader(height: 200)
                    } else {
                        Text("분석 기간을 선택해주세요")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom)
            }
            .navigationTitle("보고서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("보고서").font(Typography.screenTitle)
                }
            }
            // 화면에 처음 들어오면 기본 기간(최근 30일)으로 바로 한 번 분석해서 보여준다 — 그 다음부터는
            // 기간을 새로 고를 때만(datePickers의 onConfirm) 다시 분석한다.
            .task {
                guard !viewModel.hasAnalyzed else { return }
                await viewModel.analyze()
            }
        }
    }

    // 화면에는 별도의 "분석" 버튼이 없다 — 기간(시작일~종료일) 입력 하나를 탭하면 뜨는 시트 안에
    // 분석 버튼이 있고, 그 버튼을 누르면 시트가 닫히면서 바로 분석한다. 처음 들어왔을 때는 기본
    // 기간(최근 30일)으로 자동 분석하고, 그 뒤로는 사용자가 기간을 바꿔 다시 분석을 눌러야 한다.
    private var datePickers: some View {
        PeriodRangeRow(
            startDate: $viewModel.previousVisitDate,
            endDate: $viewModel.thisVisitDate,
            maximumDate: Date(),
            isDisabled: viewModel.isAnalyzing
        ) {
            selectedSleepRange = nil
            selectedCVDailyPoint = nil
            selectedHourPatternPoint = nil
            Task { await viewModel.analyze() }
        }
    }

    // MARK: - 기간 요약 (심박수/SDNN/rMSSD 중앙값)

    // 대시보드 스타일 — 라벨 텍스트 대신 큰 숫자 3개를 가로로 나란히 놓은 카드로 보여준다.
    private var vitalsSection: some View {
        Group {
            if let vitals = viewModel.vitalMedians,
               vitals.restingHeartRate != nil || vitals.sdnn != nil || vitals.rmssd != nil {
                HStack(spacing: 12) {
                    vitalPanel(title: "안정시 심박수", value: vitals.restingHeartRate.map { "\(Int($0.rounded()))" }, unit: "bpm")
                    vitalPanel(title: "rMSSD", value: vitals.rmssd.map { "\(Int($0.rounded()))" }, unit: "ms")
                    if authViewModel.usesResearcherTerminology {
                        vitalPanel(title: "SDNN", value: vitals.sdnn.map { "\(Int($0.rounded()))" }, unit: "ms")
                    }
                }
            } else {
                Text("해당 기간에 심박수/HRV 데이터가 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // value를 String으로 받는 이유는, 숫자+단위(bpm/ms)뿐 아니라 요일("화요일")·시간대("3시~4시")
    // 처럼 이미 포맷된 문자열도 같은 카드 스타일로 보여줘야 해서다.
    private func vitalPanel(title: String, value: String?, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(Typography.bigStatValue)
                if value != nil, let unit {
                    Text(unit)
                        .font(Typography.caption2)
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.primary50, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
    }

    // vitalPanel과 같은 "작은 라벨 + 큰 굵은 값" 조합이지만, 이미 panelCard로 감싸인 섹션
    // 안에서 쓰는 용도라 테두리/그림자는 따로 두지 않고 배경(Theme.primary50)만 준다. value를
    // 문자열이 아니라 Text로 받는 이유는, 평균 수면 시간처럼 "N시간 M분"에서 숫자는 크게·단위
    // (시간/분)는 작게 섞어서 조합해야 하는 경우가 있어서다(durationText 참고) — Text는 +로
    // 이어붙여도 조각별 폰트가 유지된다.
    private func bigStat(title: String, value: Text, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                value
                if let unit {
                    Text(unit)
                        .font(Typography.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 8))
    }

    // "N시간 M분"에서 숫자(24pt Bold)와 "시간"/"분" 단위(caption2)를 따로 스타일링해서 이어붙인다.
    private func durationText(_ interval: TimeInterval) -> Text {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return Text("\(hours)").font(Typography.bigStatValue)
            + Text("시간 ").font(Typography.caption2).foregroundStyle(.secondary)
            + Text("\(minutes)").font(Typography.bigStatValue)
            + Text("분").font(Typography.caption2).foregroundStyle(.secondary)
    }

    // averageSleepStartHourOffset(그 밤 오전 10시부터 경과한 시간)을 실제 시:분으로 되돌려서
    // durationText와 같은 스타일(숫자 크게, "시"/"분" 단위는 작게)로 보여준다.
    private func sleepStartTimeText(hourOffset: Double) -> Text {
        let minutesFromTenAM = Int((hourOffset * 60).rounded())
        let minutesOfDay = ((10 * 60 + minutesFromTenAM) % (24 * 60) + 24 * 60) % (24 * 60)
        let hour = minutesOfDay / 60
        let minute = minutesOfDay % 60
        return Text("\(hour)").font(Typography.bigStatValue)
            + Text("시 ").font(Typography.caption2).foregroundStyle(.secondary)
            + Text("\(minute)").font(Typography.bigStatValue)
            + Text("분").font(Typography.caption2).foregroundStyle(.secondary)
    }

    // MARK: - 수면

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("수면").font(Typography.reportSectionTitle)
                .padding(.bottom, 8)

            if let avgDuration = viewModel.averageSleepDuration {
                HStack(spacing: 10) {
                    bigStat(title: "평균 수면 시간", value: durationText(avgDuration))
                    if let avgStartOffset = viewModel.averageSleepStartHourOffset {
                        bigStat(title: "평균 수면 시작 시간", value: sleepStartTimeText(hourOffset: avgStartOffset))
                    }
                }
            }

            if viewModel.sleepRanges.isEmpty {
                Text("해당 기간에 수면 데이터가 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                sleepBarChart.chartLoadingOverlay(viewModel.isAnalyzing)
            }

            // 세로축이 이제 시각이라 세션마다 실제 시간대에 막대가 그려지고, 탭도 x(날짜)와
            // y(시각) 둘 다로 어느 세션인지 정확히 짚어내므로, 예전처럼 하루치를 다 나열할
            // 필요 없이 탭한 세션 하나만 보여주면 된다.
            if let selectedSleepRange {
                SleepDetailPanel(sleepRange: selectedSleepRange) { self.selectedSleepRange = nil }
            }
        }
        .panelCard()
    }

    // 오후 9시(21시) 이후에 시작해서 다음날 오전 10시 이전에 끝나는 수면을 그날 밤으로 본다 —
    // 예: 7/1 22시 취침 ~ 7/2 9시 기상은 7/1의 수면으로 표시한다. 그래서 세션이 속하는 "밤 날짜"는
    // 시작 시각의 시(hour)가 10시 이전이면 전날로 당기고, 그 외엔 시작한 날짜 그대로 쓴다.
    private func nightLabel(for date: Date) -> Date {
        SleepAnalysisService.nightLabel(for: date)
    }

    // 세로축은 그 밤 날짜의 10시부터 다음날 10시까지(24시간)를 기준 삼아 시간을 잰다 — nightLabel의
    // 날짜 배정 기준(10시 이전/이후)과 정확히 같은 경계를 써야, 그 라벨에 배정된 시각이 항상
    // 0~24 범위 안에 들어온다. 21시를 기준으로 삼았더니 21시 이전(예: 저녁 7시 낮잠)이 음수
    // 오프셋이 되어 차트 밖으로 빠지는 문제가 있었다.
    private func hourOffset(_ date: Date, from nightLabel: Date) -> Double {
        guard let reference = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: nightLabel) else { return 0 }
        return date.timeIntervalSince(reference) / 3600
    }

    private func sleepBarYRange(for range: SleepRange, nightLabel: Date) -> ClosedRange<Double> {
        let start = hourOffset(range.start, from: nightLabel)
        let end = hourOffset(range.end, from: nightLabel)
        return min(start, end)...max(start, end)
    }

    private struct SleepBarSegment: Identifiable {
        let id: UUID
        let range: SleepRange
        let label: Date
        let yRange: ClosedRange<Double>
    }

    // nightLabel은 세션의 시작 시각만으로 밤 날짜를 정하기 때문에, 세션 자체가 경계 시각(오전
    // 10시)을 걸치면(예: 9시~11시 낮잠) yRange.upperBound가 24를 넘는다 — 그대로 그리면 24를 넘는
    // 부분이 고정 0...24 y축 밖으로 잘려 보이지 않는다. 그 경우 경계에서 둘로 나눠 앞부분은 이
    // 밤 날짜의 24시(자정 아님, 경계 시각)까지, 뒷부분은 다음 밤 날짜의 0시부터로 각각 그린다.
    private func sleepBarSegments(for range: SleepRange) -> [SleepBarSegment] {
        let label = nightLabel(for: range.start)
        let yRange = sleepBarYRange(for: range, nightLabel: label)
        guard yRange.upperBound > 24 else {
            return [SleepBarSegment(id: range.id, range: range, label: label, yRange: yRange)]
        }
        let nextLabel = Calendar.current.date(byAdding: .day, value: 1, to: label) ?? label
        return [
            SleepBarSegment(id: UUID(), range: range, label: label, yRange: yRange.lowerBound...24),
            SleepBarSegment(id: UUID(), range: range, label: nextLabel, yRange: 0...(yRange.upperBound - 24)),
        ]
    }

    private var sleepBarSegmentsAll: [SleepBarSegment] {
        viewModel.sleepRanges.flatMap(sleepBarSegments)
    }

    // 세로축 눈금(0~24)을 실제 시각으로 바꾼다 — 0은 10시, 24는 다음날 10시.
    private func clockLabel(forHour hour: Double) -> String {
        "\((10 + Int(hour.rounded(.down))) % 24)"
    }

    private static let sleepYAxisTicks: [Double] = [0, 6, 12, 18, 24]

    private var sleepBarChart: some View {
        Chart {
            ForEach(sleepBarSegmentsAll) { segment in
                BarMark(
                    x: .value("날짜", segment.label, unit: .day),
                    yStart: .value("잠든 시각", segment.yRange.lowerBound),
                    yEnd: .value("일어난 시각", segment.yRange.upperBound),
                    width: .fixed(sleepBarWidth)
                )
                .foregroundStyle(Theme.sleep.opacity(0.7))
                .cornerRadius(4)
            }

            if let avgStartOffset = viewModel.averageSleepStartHourOffset {
                RuleMark(y: .value("평균 수면 시작 시각", avgStartOffset))
                    .foregroundStyle(Theme.systemGray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .frame(height: 260)
        // 하루 칸은 항상 21시~다음날 21시(24시간).
        .chartYScale(domain: 0...24)
        // y축 라벨이 차트 레이아웃 공간을 차지하지 않아야 한다는 규칙(ui-style.md,
        // HRVAnalysisView+Axes.yAxisOverlay와 동일) — 네이티브 y축은 숨기고 직접 오버레이로 그린다.
        .chartYAxis(.hidden)
        // 아래 CV 차트와 같은 도메인을 명시해야 두 차트의 x축 눈금 위치가 일치한다 — 각자 자기
        // 데이터 범위로 도메인을 추론하게 두면(수면 없는 날/CV 없는 날이 있을 때) 눈금이 어긋난다.
        .chartXScale(domain: chartDateDomain)
        .chartXAxis {
            AxisMarks(values: dateAxisTickDates) { value in
                Self.dateAxisMarks(value)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
                    xAxisBaseline(proxy: proxy, geo: geo)
                    yAxisOverlay(proxy: proxy, geo: geo, tickValues: Self.sleepYAxisTicks, label: clockLabel(forHour:))

                    if let selectedSleepRange {
                        selectedSleepBarShadow(selectedSleepRange, proxy: proxy, geo: geo)
                    }

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotRect = geo[plotFrame]
                            let localX = location.x - plotRect.minX
                            let localY = location.y - plotRect.minY
                            guard let tappedDate: Date = proxy.value(atX: localX) else { return }
                            let calendar = Calendar.current
                            let sameDaySegments = sleepBarSegmentsAll.filter {
                                calendar.isDate($0.label, inSameDayAs: tappedDate)
                            }
                            // 같은 날짜에 세션이 여러 개면(예: 이른 아침에 잠깐 더 잔 것 + 그날
                            // 밤잠) 탭한 세로 위치와 가장 가까운 세션을 고른다 — x만으로는 그날
                            // 중 어느 세션인지 구분이 안 된다.
                            if let tappedHour: Double = proxy.value(atY: localY) {
                                selectedSleepRange = sameDaySegments.min {
                                    distance(from: tappedHour, to: $0.yRange) < distance(from: tappedHour, to: $1.yRange)
                                }?.range
                            } else {
                                selectedSleepRange = sameDaySegments.first?.range
                            }
                        }
                }
            }
        }
        .background {
            // 오늘의 패턴 월별 막대와 같은 방식 — plot 폭을 날짜 수만큼 나눠 막대 너비를 정하고,
            // 같은 너비를 선택 그림자에도 그대로 써서 실제 막대와 정확히 겹치게 한다.
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateSleepBarWidth(plotWidth: geo.size.width) }
                    .onChange(of: geo.size.width) { _, newWidth in
                        updateSleepBarWidth(plotWidth: newWidth)
                    }
            }
        }
    }

    // 실제 수면 데이터가 있는 날짜의 min~max가 아니라, 차트에 표시되는 전체 도메인
    // (chartDateDomain) 기준으로 날짜 수를 세야 한다 — 데이터 없는 날이 있으면
    // min~max 기준 날짜 수가 실제 도메인보다 적어져서, 그 좁은 날짜 수로 나눈 막대 너비가 실제
    // 하루 칸보다 넓어져 막대끼리 겹친다.
    private var sleepChartDayCount: Int {
        let days = Calendar.current.dateComponents(
            [.day],
            from: chartDateDomain.lowerBound,
            to: chartDateDomain.upperBound
        ).day ?? 0
        // chartDateDomain.upperBound가 마지막 날 자정보다 하루 더 뒤(다음 날 자정)라
        // 날짜 수 자체가 이미 +1이 반영된 값이라 여기서 다시 더하지 않는다.
        return max(days, 1)
    }

    private func updateSleepBarWidth(plotWidth: CGFloat) {
        let bandwidth = plotWidth / CGFloat(sleepChartDayCount)
        sleepBarWidth = (bandwidth * 0.6).clamped(to: 3...30)
    }

    // 네이티브 AxisMarks는 눈금마다 찍는 세로 그리드/틱만 그리고, 플롯 하단을 가로지르는 축
    // 기준선은 그리지 않는다 — HRVAnalysisView+Axes.xAxisOverlay와 같은 색(Color(white: 0.35))으로
    // 직접 그려서 맞춘다.
    @ViewBuilder
    private func xAxisBaseline(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotFrame = proxy.plotFrame {
            let plotRect = geo[plotFrame]
            Path { path in
                path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
            }
            .stroke(Color(white: 0.35), lineWidth: 1)
        }
    }

    // BarMark(x: .value(_, range.start, unit: .day))는 그 날 전체 구간 중앙에 그려지므로,
    // 그림자도 같은 중앙 좌표를 써야 실제 막대와 겹친다(HRVAnalysisView+Axes.monthMidpoint와 동일한 이유).
    private func dayMidpoint(of date: Date) -> Date {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return date }
        return interval.start.addingTimeInterval(interval.duration / 2)
    }

    // 탭한 세로 위치(hour)가 어떤 세션의 [시작, 종료] 시각 구간에서 얼마나 떨어져 있는지 —
    // 구간 안이면 0, 밖이면 가장 가까운 경계까지의 거리.
    private func distance(from hour: Double, to range: ClosedRange<Double>) -> Double {
        if range.contains(hour) { return 0 }
        return min(abs(hour - range.lowerBound), abs(hour - range.upperBound))
    }

    // 오늘의 패턴 Gantt 차트의 선택 그림자와 같은 스타일(그림자 색·반경·오프셋, 모서리 반경) —
    // 차트 마크 자체는 shadow()를 지원하지 않아서 같은 위치·크기·색의 실제 도형을 겹쳐 그린다.
    @ViewBuilder
    private func selectedSleepBarShadow(_ range: SleepRange, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        // 경계 시각(10시)을 걸친 세션은 세그먼트가 두 개로 나뉘어 있으므로, 선택된 세션에 속하는
        // 세그먼트 각각에 그림자를 그려야 두 조각 모두 강조된다.
        ForEach(sleepBarSegmentsAll.filter { $0.range.id == range.id }) { segment in
            if let plotFrame = proxy.plotFrame,
               let x = proxy.position(forX: dayMidpoint(of: segment.label)),
               let yTop = proxy.position(forY: segment.yRange.upperBound),
               let yBottom = proxy.position(forY: segment.yRange.lowerBound) {
                let plotRect = geo[plotFrame]
                // 선택 안 된 막대는 Theme.sleep.opacity(0.7)라 반투명 위에 반투명을 겹치면 뿌옇게
                // 흐려 보인다 — 선택된 막대는 불투명 단색으로 확실히 구분되게 그린다.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.sleep)
                    .frame(width: sleepBarWidth, height: abs(yBottom - yTop))
                    .position(x: plotRect.minX + x, y: plotRect.minY + (yTop + yBottom) / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // y축 라벨이 차트 레이아웃 공간을 차지하지 않고 고정된 위치에 떠 있어야 한다는 규칙(ui-style.md,
    // HRVAnalysisView+Axes.yAxisOverlay와 동일한 스타일) — 네이티브 y축 대신 이 오버레이로 그린다.
    @ViewBuilder
    private func yAxisOverlay(proxy: ChartProxy, geo: GeometryProxy, tickValues: [Double], label: @escaping (Double) -> String) -> some View {
        if let plotFrame = proxy.plotFrame {
            let plotRect = geo[plotFrame]
            ForEach(tickValues, id: \.self) { value in
                if let y = proxy.position(forY: value) {
                    Path { path in
                        path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY + y))
                        path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.minY + y))
                    }
                    // 보고서는 여러 차트를 한 화면에 쌓아 보여주므로 가로선이 겹쳐 진해 보이지
                    // 않도록, 세로 그리드(0.25)보다 더 옅게 둔다.
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)

                    Text(label(value))
                        .font(Typography.chartAxisLabel)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .background(Color(.systemBackground).opacity(0.85))
                        .position(x: plotRect.minX + 16, y: plotRect.minY + y)
                }
            }
        }
    }

    // MARK: - rMSSD 추이

    private var cvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("rMSSD 추이").font(Typography.reportSectionTitle)
                if let findings = viewModel.cvFindings {
                    averageCVChip(findings.overallCV)
                }
            }
            .padding(.bottom, 8)

            if let findings = viewModel.cvFindings {
                if let displayedPoint = cvDisplayedPoint(in: findings.dailyPoints) {
                    cvSelectionSummary(displayedPoint)
                }
                VStack(spacing: 10) {
                    cvChart(findings).chartLoadingOverlay(viewModel.isAnalyzing)
                    HStack(spacing: 10) {
                        hourlyPatternLegendItem(label: "평균") {
                            Rectangle()
                                .fill(Theme.rmssd)
                                .frame(width: 12, height: 2)
                        }
                        hourlyPatternLegendItem(label: "7일 이동 표준편차") {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.rmssd.opacity(0.15))
                                .frame(width: 12, height: 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    // design-system.md Chip 스펙(15pt Medium) — 기간 내 전체 원시 샘플 분포로 계산한 CV를
    // "평균"으로 오해하지 않도록 CV라고 명시한다.
    private func averageCVChip(_ value: Double) -> some View {
        Text("CV \(String(format: "%.1f", value))%")
            .font(Typography.secondary.weight(.semibold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.primary50, in: Capsule())
    }

    private func cvChart(_ findings: ReportViewModel.CVFindings) -> some View {
        Chart {
            // AreaMark를 먼저 그려서 뒤에 깔고, LineMark를 나중에 그려서 그 위로 보이게 한다
            // (Swift Charts는 먼저 선언된 마크 위에 나중 마크를 겹쳐 그린다).
            ForEach(findings.dailyPoints) { point in
                AreaMark(
                    x: .value("날짜", point.date, unit: .day),
                    yStart: .value("평균-표준편차", point.lowerBand),
                    yEnd: .value("평균+표준편차", point.upperBand)
                )
                .foregroundStyle(Theme.rmssd.opacity(0.15))
            }
            ForEach(findings.dailyPoints) { point in
                LineMark(
                    x: .value("날짜", point.date, unit: .day),
                    y: .value("일별 평균", point.mean)
                )
                .foregroundStyle(Theme.rmssd)
            }
            if let selectedCVDailyPoint = cvDisplayedPoint(in: findings.dailyPoints) {
                PointMark(
                    x: .value("선택 날짜", selectedCVDailyPoint.date, unit: .day),
                    y: .value("선택 평균", selectedCVDailyPoint.mean)
                )
                .symbolSize(45)
                .foregroundStyle(Theme.rmssd)
            }
        }
        .frame(height: 180)
        // y축 라벨이 차트 레이아웃 공간을 차지하지 않아야 한다는 규칙(ui-style.md) — 수면
        // 차트와 같은 이유로 네이티브 y축은 숨기고 직접 오버레이로 그린다.
        .chartYScale(domain: 0...(cvYAxisTicks(findings).last ?? 100))
        .chartYAxis(.hidden)
        // 위 수면 차트와 같은 도메인 — 두 차트가 같은 x축 눈금을 공유하게 한다.
        .chartXScale(domain: chartDateDomain)
        .chartXAxis {
            AxisMarks(values: dateAxisTickDates) { value in
                Self.dateAxisMarks(value)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
                    xAxisBaseline(proxy: proxy, geo: geo)
                    yAxisOverlay(
                        proxy: proxy,
                        geo: geo,
                        tickValues: cvYAxisTicks(findings),
                        label: { String(format: "%.0f", $0) }
                    )

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotRect = geo[plotFrame]
                            let localX = location.x - plotRect.minX
                            guard localX >= 0, localX <= plotRect.width,
                                  let tappedDate: Date = proxy.value(atX: localX) else { return }
                            selectedCVDailyPoint = findings.dailyPoints.min {
                                abs($0.date.timeIntervalSince(tappedDate))
                                    < abs($1.date.timeIntervalSince(tappedDate))
                            }
                        }
                }
            }
        }
    }

    private func cvSelectionSummary(_ point: ReportViewModel.CVDailyPoint) -> some View {
        let standardDeviation = (point.upperBand - point.lowerBand) / 2
        return HStack(spacing: 8) {
            Text(ReportView.dateFormatter.string(from: point.date))
            Spacer(minLength: 4)
            Text("평균")
                .foregroundStyle(.secondary)
            Text("\(Int(point.mean.rounded()))ms")
                .bold()
            Text("표준편차")
                .foregroundStyle(.secondary)
            Text("\(Int(standardDeviation.rounded()))ms")
                .bold()
        }
        .font(Typography.caption)
        .lineLimit(1)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 사용자가 아직 날짜를 탭하지 않았으면 분석 기간에서 가장 최근 일별 값을 기본 선택한다.
    private func cvDisplayedPoint(
        in points: [ReportViewModel.CVDailyPoint]
    ) -> ReportViewModel.CVDailyPoint? {
        selectedCVDailyPoint ?? points.max { $0.date < $1.date }
    }

    // rMSSD(ms) 값 범위에 맞춰 0부터 대략 4등분한 "깔끔한" 눈금값을 계산한다 — 네이티브
    // AxisMarks(automatic)를 대신하는 값이라, 위에서 chartYScale의 상한도 이 값의 마지막(4*step)과
    // 맞춰서 커스텀 오버레이 눈금과 실제 축 범위가 어긋나지 않게 한다.
    private func cvYAxisTicks(_ findings: ReportViewModel.CVFindings) -> [Double] {
        let maxValue = findings.dailyPoints.map(\.upperBand).max() ?? 0
        guard maxValue > 0 else { return [0] }
        let step = max((maxValue / 4).rounded(.up), 10)
        return Array(stride(from: 0, through: step * 4, by: step))
    }

    // MARK: - 하루 패턴

    // 선택 기간 전체를 시(0~23)별로 뭉친 분포 차트 — 평균±표준편차 박스와 평균 가로선을
    // 월별 캔들 차트와 유사한 형태로 겹쳐 그린다.
    private var hourlyPatternSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("시간대별 rMSSD 분포")
                .font(Typography.reportSectionTitle)
                .padding(.bottom, 8)

            if viewModel.hourOfDayPattern.isEmpty {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let displayedPoint = hourlyPatternDisplayedPoint(in: viewModel.hourOfDayPattern) {
                    hourlyPatternSelectionSummary(displayedPoint)
                }
                VStack(spacing: 10) {
                    hourlyPatternChart(viewModel.hourOfDayPattern).chartLoadingOverlay(viewModel.isAnalyzing)
                    HStack(spacing: 10) {
                        hourlyPatternLegendItem(label: "평균") {
                            Rectangle()
                                .fill(Theme.rmssd)
                                .frame(width: 12, height: 2)
                        }
                        hourlyPatternLegendItem(label: "±표준편차") {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.rmssdRange)
                                .frame(width: 6, height: 10)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .panelCard()
    }

    private func hourlyPatternLegendItem<Swatch: View>(
        label: String,
        @ViewBuilder swatch: () -> Swatch
    ) -> some View {
        HStack(spacing: 4) {
            swatch()
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func hourlyPatternChart(_ points: [ReportViewModel.HourOfDayPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                let isSelected = hourlyPatternDisplayedPoint(in: points)?.id == point.id
                RectangleMark(
                    x: .value("시", point.hour),
                    yStart: .value("평균-표준편차", point.lowerBand),
                    yEnd: .value("평균+표준편차", point.upperBand),
                    width: .fixed(6)
                )
                .foregroundStyle(isSelected ? Theme.rmssd.opacity(0.45) : Theme.rmssdRange)
                .cornerRadius(4)

                RectangleMark(
                    x: .value("시", point.hour),
                    y: .value("평균", point.mean),
                    width: .fixed(6),
                    height: .fixed(2)
                )
                .foregroundStyle(Theme.rmssd)
            }

        }
        .frame(height: 180)
        .chartXScale(domain: 0...23)
        .chartYScale(domain: 0...(hourlyPatternYAxisTicks(points).last ?? 100))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisGridLine().foregroundStyle(.gray.opacity(0.25))
                AxisTick().foregroundStyle(.gray.opacity(0.85))
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)시")
                            .font(Typography.chartAxisLabel)
                            .tracking(1)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
                    xAxisBaseline(proxy: proxy, geo: geo)
                    yAxisOverlay(
                        proxy: proxy,
                        geo: geo,
                        tickValues: hourlyPatternYAxisTicks(points),
                        label: { String(format: "%.0f", $0) }
                    )

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let plotRect = geo[plotFrame]
                            let localX = location.x - plotRect.minX
                            guard localX >= 0, localX <= plotRect.width,
                                  let tappedHour: Double = proxy.value(atX: localX) else { return }
                            selectedHourPatternPoint = points.min {
                                abs(Double($0.hour) - tappedHour) < abs(Double($1.hour) - tappedHour)
                            }
                        }

                }
            }
        }
    }

    private func hourlyPatternSelectionSummary(_ point: ReportViewModel.HourOfDayPoint) -> some View {
        HStack(spacing: 8) {
            Text("\(point.hour)시 ~ \((point.hour + 1) % 24)시")
            Spacer(minLength: 4)
            Text("평균")
                .foregroundStyle(.secondary)
            Text("\(Int(point.mean.rounded()))ms")
                .bold()
            Text("표준편차")
                .foregroundStyle(.secondary)
            Text("\(Int(point.standardDeviation.rounded()))")
                .bold()
        }
        .font(Typography.caption)
        .lineLimit(1)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 아직 탭한 시간대가 없으면 선택 기간에서 평균 rMSSD가 가장 낮은 시간대를 기본 선택으로 쓴다.
    private func hourlyPatternDisplayedPoint(
        in points: [ReportViewModel.HourOfDayPoint]
    ) -> ReportViewModel.HourOfDayPoint? {
        selectedHourPatternPoint ?? points.min { $0.mean < $1.mean }
    }

    private func hourlyPatternYAxisTicks(_ points: [ReportViewModel.HourOfDayPoint]) -> [Double] {
        let maxValue = points.map(\.upperBand).max() ?? 0
        guard maxValue > 0 else { return [0] }
        let step = max((maxValue / 4).rounded(.up), 10)
        return Array(stride(from: 0, through: step * 4, by: step))
    }

    // MARK: - rMSSD

    // vitalsSection과 같은 스타일(vitalPanel)로, 같은 너비로 나란히 두 패널만 보여준다 —
    // "가장 낮은 날짜"·그날 컨텍스트 같은 세부 텍스트 없이 요일/시간대 두 값만 담당한다.
    private var rmssdLowestFindingsSection: some View {
        Group {
            if let findings = viewModel.rmssdFindings {
                HStack(spacing: 12) {
                    vitalPanel(
                        title: "가장 낮은 요일",
                        value: findings.lowestAverageWeekday.flatMap { weekday in
                            Self.weekdaySymbols.indices.contains(weekday - 1) ? Self.weekdaySymbols[weekday - 1] : nil
                        }
                    )
                    vitalPanel(
                        title: "낮은 시간대",
                        value: findings.mostFrequentLowestHour.map { "\($0)시~\($0 + 1)시" }
                    )
                }
            }
        }
    }

    private var rmssdLowestDaysTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rMSSD 낮은 날 Top \(viewModel.rmssdLowestDayRows.count)").font(Typography.reportSectionTitle)
                .padding(.bottom, 8)

            if viewModel.rmssdLowestDayRows.isEmpty {
                Text("해당 기간에 비교할 데이터가 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
                // 표(Grid)는 "스케줄" 칸이 길어지면 다른 칸까지 좁아져 읽기 불편했다 — 날짜별로
                // 카드 하나씩 쌓아서, 왼쪽에 날짜+rMSSD 값, 오른쪽에 라벨 붙은 상세 줄로 나눈다.
                // alignment를 명시하지 않으면 기본값(center)이라 행마다 너비가 달라 왼쪽이
                // 들쭉날쭉해 보인다 — leading으로 고정한다.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.rmssdLowestDayRows) { row in
                        lowestDayRow(row)
                    }
                }
            }
        }
        .panelCard()
    }

    private func lowestDayRow(_ row: ReportViewModel.RMSSDLowestDayRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFormatter.string(from: row.date))
                .font(Typography.caption.bold())

            HStack(alignment: .top, spacing: 12) {
                lowestDayChip(
                    label: "rMSSD",
                    value: Text("\(Int(row.rmssd.rounded()))")
                        .font(Typography.sectionTitle)
                        + Text("ms").font(Typography.caption2).fontWeight(.regular),
                    color: Theme.primary50
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        lowestDayInlineDetail(label: "수면", value: row.previousNightSleepDuration.map(SleepAnalysisService.formattedDuration))
                        lowestDayInlineDetail(label: "운동", value: row.previousDayExerciseSummary)
                    }
                    lowestDayDetailLine(label: "스케줄", value: row.scheduleTitles.isEmpty ? nil : row.scheduleTitles.joined(separator: ", "))
                }
            }
        }
        .padding(.bottom, 10)
    }

    // 라벨 위, 값 아래로 줄바꿈해서 담는 작은 칩 — rMSSD 전용. value를 Text로 받는 이유는
    // durationText/bigStat과 같은 이유 — 숫자(20pt Bold)와 단위(ms, caption2 Regular)를 따로
    // 스타일링해서 이어붙여야 해서다.
    private func lowestDayChip(label: String, value: Text, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.caption2.bold())
                .foregroundStyle(.secondary)
            value
                .foregroundStyle(Theme.primary600)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color, in: RoundedRectangle(cornerRadius: 6))
    }

    // 수면/운동 — 라벨은 그대로, 값만 볼드로 강조해서 가로로 나란히 둔다.
    private func lowestDayInlineDetail(label: String, value: String?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(Typography.caption.bold())
        }
    }

    // 스케줄 — 라벨과 값을 옆으로 붙이지 않고 줄바꿈해서 위/아래로 둔다(스케줄 여러 개가
    // 길게 이어질 수 있어서 한 줄에 라벨과 나란히 두면 좁아 보인다).
    private func lowestDayDetailLine(label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Typography.caption.bold())
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(Typography.caption)
        }
    }

}

// 수면/CV처럼 섹션을 감싸는 카드 — vitalPanel(배경 Theme.primary50)과 달리
// 배경은 흰색, 테두리는 기본 색(Theme.systemGray5)을 쓴다.
private extension View {
    func panelCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
    }
}

// 시작일/종료일을 각자 입력칸으로 나누는 대신, 하나의 입력(버튼)에 "시작일 ~ 종료일"을 같이
// 보여주고 탭하면 아래에서 시트 하나가 올라와 compact 스타일 피커 두 개를 나란히 고르게 한다 —
// 각 피커가 독립적으로 달을 넘길 수 있어서 시작일과 종료일이 서로 다른 달에 있어도 그대로
// 고를 수 있다. 화면에 있던 "분석" 버튼은 따로 두지 않고 이 시트 안으로 옮겨서, 기간을 다 고른
// 뒤 그 버튼 한 번으로 검색과 동시에 시트가 닫히게 한다.
private struct PeriodRangeRow: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var maximumDate: Date?
    var isDisabled: Bool = false
    var onAnalyze: () -> Void

    private struct SheetSelection: Identifiable {
        let id = UUID()
        let startDate: Date
        let endDate: Date
    }

    @State private var sheetSelection: SheetSelection?

    var body: some View {
        Button {
            sheetSelection = SheetSelection(startDate: startDate, endDate: endDate)
        } label: {
            HStack {
                Text("\(ReportView.dateFormatter.string(from: startDate)) ~ \(ReportView.dateFormatter.string(from: endDate))")
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.systemGray5, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .sheet(item: $sheetSelection) { selection in
            PeriodRangeSheet(
                initialStartDate: selection.startDate,
                initialEndDate: selection.endDate,
                maximumDate: maximumDate,
                isDisabled: isDisabled
            ) { selectedStartDate, selectedEndDate in
                startDate = selectedStartDate
                endDate = selectedEndDate
                sheetSelection = nil
                onAnalyze()
            }
        }
    }
}

private struct PeriodRangeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date

    let maximumDate: Date?
    let isDisabled: Bool
    let onAnalyze: (Date, Date) -> Void

    init(
        initialStartDate: Date,
        initialEndDate: Date,
        maximumDate: Date?,
        isDisabled: Bool,
        onAnalyze: @escaping (Date, Date) -> Void
    ) {
        _draftStartDate = State(initialValue: Calendar.current.startOfDay(for: initialStartDate))
        _draftEndDate = State(initialValue: Self.endOfDay(initialEndDate))
        self.maximumDate = maximumDate
        self.isDisabled = isDisabled
        self.onAnalyze = onAnalyze
    }

    private var maximumSelectableDate: Date {
        guard let maximumDate else { return .distantFuture }
        return Calendar.current.startOfDay(for: maximumDate)
    }

    nonisolated private static func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: calendar.startOfDay(for: date)) ?? date
    }

    private func datePicker(
        for date: Binding<Date>,
        title: String,
        range: ClosedRange<Date>,
        normalize: @escaping (Date) -> Date = { Calendar.current.startOfDay(for: $0) }
    ) -> some View {
        // DatePicker가 고른 날짜를 정확히 자정으로 돌려주지 않을 수 있어서(구현에 따라 다름), 여기서
        // 항상 정해진 시각(시작일은 자정, 종료일은 23:59:59)으로 정규화해 저장한다 — 그래야 이 값을
        // 다시 다른 range의 경계로 쓸 때(예: 종료일 range의 하한이 시작일) 시각 차이 때문에 범위가
        // 뒤집히는 일이 없고, 종료 날짜의 데이터도 확실히 포함된다.
        let normalized = Binding<Date>(
            get: { date.wrappedValue },
            set: { date.wrappedValue = normalize($0) }
        )
        return DatePicker(title, selection: normalized, in: range, displayedComponents: .date)
            .datePickerStyle(.compact)
            // 날짜에 따라 "7월 1일"/"12월 25일"처럼 표시 텍스트 길이가 달라져서 옆의 "~"와
            // 상대 피커가 좌우로 밀리는 걸 막는다 — 폭을 고정해서 어떤 날짜든 같은 자리에 보이게 한다.
            .frame(width: 130)
            .labelsHidden()
    }

    private var hasValidDraftRange: Bool {
        Calendar.current.startOfDay(for: draftStartDate) <= Calendar.current.startOfDay(for: draftEndDate)
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack(spacing: 8) {
                    datePicker(
                        for: $draftStartDate,
                        title: "시작일",
                        range: Date.distantPast...maximumSelectableDate
                    )
                    Text("~").foregroundStyle(.secondary)
                    datePicker(
                        for: $draftEndDate,
                        title: "종료일",
                        range: Date.distantPast...Self.endOfDay(maximumSelectableDate),
                        normalize: Self.endOfDay
                    )
                }
                .padding()

                if !hasValidDraftRange {
                    Text("종료일은 시작일과 같거나 이후여야 해요.")
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onAnalyze(draftStartDate, draftEndDate)
                } label: {
                    Label("분석", systemImage: "waveform.path.ecg")
                        .font(Typography.cardTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled || !hasValidDraftRange)
                .padding()
                .background(.bar)
            }
            .navigationTitle("분석 기간")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.locale, Locale(identifier: "ko_KR"))
        .presentationDetents([.height(250)])
    }
}

// 기간을 다시 골라 재분석하는 동안에도 이전 차트를 화면에 그대로 두고, 그 위에 로딩 중임을
// 겹쳐 보여준다 — 전체 화면이 로더로 바뀌면 방금까지 보던 결과가 사라져 어색하다.
private struct ChartLoadingOverlay: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                ZStack {
                    Color(.systemBackground).opacity(0.6)
                    HeartLoader(height: 60)
                }
            }
        }
    }
}

private extension View {
    func chartLoadingOverlay(_ isLoading: Bool) -> some View {
        modifier(ChartLoadingOverlay(isLoading: isLoading))
    }
}

#Preview {
    ReportView()
        .environment(AuthViewModel())
}
