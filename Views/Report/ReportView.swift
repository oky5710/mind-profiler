import Charts
import SwiftUI

struct ReportView: View {
    @State private var viewModel = ReportViewModel()
    @State private var selectedSleepRange: SleepRange?
    // 오늘의 패턴 Gantt 차트와 같은 방식(고정 픽셀 너비)으로 선택 그림자를 그리려고 실측한다.
    @State private var sleepBarWidth: CGFloat = 20

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let weekdaySymbols = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]

    // ui-style.md "날짜 표기" 규칙 — 인접 포인트 간격이 하루 이상 30일 미만이면 MM-dd 표기.
    // 이 화면의 차트는 항상 날짜 단위(하루 간격) 데이터라 이 축약 규칙 하나만 해당한다.
    // 포맷 자체는 HRVAnalysisView.monthDayFormatter를 그대로 재사용해 앱 전체에서 동일하게 유지한다.
    // ui-style.md "그리드 라인은 옅게, 눈금 틱은 그보다 진하게" — HRVAnalysisView와 같은 값
    // (그리드 .gray.opacity(0.25), 틱 .gray.opacity(0.85))과 같은 라벨 폰트(9pt)를 그대로 맞춘다.
    @AxisMarkBuilder
    private static func dateAxisMarks(_ value: AxisValue) -> some AxisMark {
        AxisGridLine().foregroundStyle(.gray.opacity(0.25))
        AxisTick().foregroundStyle(.gray.opacity(0.85))
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(HRVAnalysisView.monthDayFormatter.string(from: date))
                    .font(.system(size: 9))
                    .tracking(1)
            }
        }
    }

    // y축도 x축과 같은 9pt로 맞춘다(HRVAnalysisView의 yAxisOverlay와 동일한 크기).
    @AxisMarkBuilder
    private static func valueAxisMarks(_ value: AxisValue) -> some AxisMark {
        AxisGridLine().foregroundStyle(.gray.opacity(0.25))
        AxisTick().foregroundStyle(.gray.opacity(0.85))
        AxisValueLabel()
            .font(.system(size: 9))
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
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if viewModel.isAnalyzing {
                        HeartLoader(height: 200)
                    } else if viewModel.hasAnalyzed {
                        vitalsSection
                        sleepSection
                        cvSection
                        rmssdSection
                        rmssdLowestDaysTableSection
                        sdnnRmssdSection
                        correlationSection
                    } else {
                        Text("분석 기간을 선택해주세요")
                            .font(.footnote)
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
        }
    }

    // 화면에는 별도의 "분석" 버튼이 없다 — 기간(시작일~종료일) 입력 하나를 탭하면 뜨는 시트 안에
    // 분석 버튼이 있고, 그 버튼을 누르면 시트가 닫히면서 바로 분석한다. 처음 들어왔을 때는 자동으로
    // 분석하지 않고 "분석 기간을 선택해주세요" 안내만 보여준다 — 사용자가 직접 기간을 확인/조정하고
    // 분석을 눌러야 한다.
    private var datePickers: some View {
        PeriodRangeRow(
            startDate: $viewModel.previousVisitDate,
            endDate: $viewModel.thisVisitDate,
            maximumDate: Date(),
            isDisabled: viewModel.isAnalyzing
        ) {
            selectedSleepRange = nil
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
                    vitalPanel(title: "안정시 심박수", value: vitals.restingHeartRate.map { Int($0.rounded()) }, unit: "bpm")
                    vitalPanel(title: "rMSSD", value: vitals.rmssd.map { Int($0.rounded()) }, unit: "ms")
                    vitalPanel(title: "SDNN", value: vitals.sdnn.map { Int($0.rounded()) }, unit: "ms")
                }
            } else {
                Text("해당 기간에 심박수/HRV 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func vitalPanel(title: String, value: Int?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "—")
                    .font(.system(size: 28, weight: .bold))
                if value != nil {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.primary50, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
        // 광원이 좌상단에 있다고 가정 — 그림자는 반대 방향인 우하단으로 옅게 떨어뜨린다.
        .shadow(color: .black.opacity(0.1), radius: 4, x: 2, y: 2)
    }

    // vitalPanel과 같은 "작은 라벨 + 큰 굵은 값" 조합이지만, 이미 panelCard로 감싸인 섹션
    // 안에서 쓰는 용도라 카드 배경/테두리는 따로 두지 않는다. value를 문자열이 아니라 Text로 받는
    // 이유는, 평균 수면 시간처럼 "N시간 M분"에서 숫자는 크게·단위(시간/분)는 작게 섞어서 조합해야
    // 하는 경우가 있어서다(durationText 참고) — Text는 +로 이어붙여도 조각별 폰트가 유지된다.
    private func bigStat(title: String, value: Text, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                value
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let bigStatValueFont = Font.system(size: 24, weight: .bold)

    // "N시간 M분"에서 숫자(24pt Bold)와 "시간"/"분" 단위(caption2)를 따로 스타일링해서 이어붙인다.
    private func durationText(_ interval: TimeInterval) -> Text {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return Text("\(hours)").font(Self.bigStatValueFont)
            + Text("시간 ").font(.caption2).foregroundStyle(.secondary)
            + Text("\(minutes)").font(Self.bigStatValueFont)
            + Text("분").font(.caption2).foregroundStyle(.secondary)
    }

    // MARK: - 수면

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("수면").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if let avgDuration = viewModel.averageSleepDuration, let avgScore = viewModel.averageSleepScore {
                HStack(spacing: 24) {
                    bigStat(title: "평균 수면 시간", value: durationText(avgDuration))
                    bigStat(title: "평균 수면 점수", value: Text("\(Int(avgScore.rounded()))").font(Self.bigStatValueFont), unit: "점")
                }
            }

            if viewModel.sleepRanges.isEmpty {
                Text("해당 기간에 수면 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                sleepBarChart
            }

            if let selectedSleepRange {
                SleepDetailPanel(sleepRange: selectedSleepRange) { self.selectedSleepRange = nil }
            }
        }
        .panelCard()
    }

    private var sleepBarChart: some View {
        Chart {
            ForEach(viewModel.sleepRanges) { range in
                let hours = range.end.timeIntervalSince(range.start) / 3600
                BarMark(
                    x: .value("날짜", range.start, unit: .day),
                    y: .value("수면 시간", hours),
                    width: .fixed(sleepBarWidth)
                )
                .foregroundStyle(Theme.sleep.opacity(0.7))
                .cornerRadius(4)
            }
            if let avgDuration = viewModel.averageSleepDuration {
                RuleMark(y: .value("평균", avgDuration / 3600))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .frame(height: 180)
        .chartYAxisLabel("시간")
        .chartYAxis {
            AxisMarks { value in
                Self.valueAxisMarks(value)
            }
        }
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
                            guard let tappedDate: Date = proxy.value(atX: localX) else { return }
                            selectedSleepRange = viewModel.sleepRanges.min {
                                abs($0.start.timeIntervalSince(tappedDate)) < abs($1.start.timeIntervalSince(tappedDate))
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
        sleepBarWidth = (bandwidth * 0.6).clamped(to: 10...30)
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

    // 오늘의 패턴 Gantt 차트의 선택 그림자와 같은 스타일(그림자 색·반경·오프셋, 모서리 반경) —
    // 차트 마크 자체는 shadow()를 지원하지 않아서 같은 위치·크기·색의 실제 도형을 겹쳐 그린다.
    @ViewBuilder
    private func selectedSleepBarShadow(_ range: SleepRange, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let hours = range.end.timeIntervalSince(range.start) / 3600
        if let plotFrame = proxy.plotFrame,
           let x = proxy.position(forX: dayMidpoint(of: range.start)),
           let yTop = proxy.position(forY: hours),
           let yBottom = proxy.position(forY: 0) {
            let plotRect = geo[plotFrame]
            // 선택 안 된 막대는 Theme.sleep.opacity(0.7)라 반투명 위에 반투명을 겹치면 뿌옇게
            // 흐려 보인다 — 선택된 막대는 불투명 단색으로 확실히 구분되게 그린다.
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.sleep)
                .frame(width: sleepBarWidth, height: abs(yBottom - yTop))
                .position(x: plotRect.minX + x, y: plotRect.minY + (yTop + yBottom) / 2)
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 변동계수 (CV)

    private var cvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("변동계수 (CV)").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if let findings = viewModel.cvFindings {
                Text("변동계수 \(String(format: "%.1f", findings.overallCV))%")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                cvChart(findings)
            } else {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
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
        }
        .frame(height: 180)
        .chartYAxisLabel("rMSSD (ms)")
        .chartYAxis {
            AxisMarks { value in
                Self.valueAxisMarks(value)
            }
        }
        // 위 수면 차트와 같은 도메인 — 두 차트가 같은 x축 눈금을 공유하게 한다.
        .chartXScale(domain: chartDateDomain)
        .chartXAxis {
            AxisMarks(values: dateAxisTickDates) { value in
                Self.dateAxisMarks(value)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                xAxisBaseline(proxy: proxy, geo: geo)
            }
        }
    }

    // MARK: - rMSSD

    private var rmssdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rMSSD").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if let findings = viewModel.rmssdFindings {
                if let lowestDate = findings.lowestDailyDate {
                    Text("가장 낮은 날: \(Self.dateFormatter.string(from: lowestDate))")
                        .font(.footnote)
                    if let context = findings.lowestDayContext {
                        lowestDayContextView(context, lowestDate: lowestDate)
                    }
                }
                if let weekday = findings.lowestAverageWeekday, Self.weekdaySymbols.indices.contains(weekday - 1) {
                    Text("평균적으로 가장 낮은 요일: \(Self.weekdaySymbols[weekday - 1])")
                        .font(.footnote)
                }
                if let hour = findings.mostFrequentLowestHour {
                    Text("자주 낮은 시간대: \(hour)시~\(hour + 1)시")
                        .font(.footnote)
                }
            } else {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 전날/당일 수면·일정을 " · "로 이어붙인 한 줄 대신, 각 값을 실제 날짜와 함께 별도 줄로 보여준다.
    @ViewBuilder
    private func lowestDayContextView(_ context: ReportViewModel.LowestDayContext, lowestDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let duration = context.previousNightDuration,
               let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: lowestDate) {
                Text("\(Self.dateFormatter.string(from: previousDay)) 수면 \(SleepAnalysisService.formattedDuration(duration))")
            }
            if let duration = context.sameNightDuration {
                Text("\(Self.dateFormatter.string(from: lowestDate)) 수면 \(SleepAnalysisService.formattedDuration(duration))")
            }
            if !context.eventTitles.isEmpty {
                Text("일정: \(context.eventTitles.joined(separator: ", "))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var rmssdLowestDaysTableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rMSSD 낮은 날 Top \(viewModel.rmssdLowestDayRows.count)").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if viewModel.rmssdLowestDayRows.isEmpty {
                Text("해당 기간에 비교할 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("일자").font(.caption2).foregroundStyle(.secondary)
                        Text("전날 수면시간").font(.caption2).foregroundStyle(.secondary)
                        Text("스케줄").font(.caption2).foregroundStyle(.secondary)
                        Text("전날 운동").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.rmssdLowestDayRows) { row in
                        GridRow {
                            Text(Self.dateFormatter.string(from: row.date)).font(.caption2)
                            Text(row.previousNightSleepDuration.map(SleepAnalysisService.formattedDuration) ?? "—")
                                .font(.caption2)
                            Text(row.scheduleTitles.isEmpty ? "—" : row.scheduleTitles.joined(separator: ", "))
                                .font(.caption2)
                            Text(row.previousDayExerciseSummary ?? "—").font(.caption2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - SDNN vs rMSSD

    private var sdnnRmssdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SDNN vs rMSSD 차이 Top 3").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if viewModel.topSDNNRMSSDDifferences.isEmpty {
                Text("해당 기간에 비교할 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("일시").font(.caption2).foregroundStyle(.secondary)
                        Text("SDNN").font(.caption2).foregroundStyle(.secondary)
                        Text("rMSSD").font(.caption2).foregroundStyle(.secondary)
                        Text("차이").font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.topSDNNRMSSDDifferences) { diff in
                        GridRow {
                            Text(Self.dateTimeFormatter.string(from: diff.date)).font(.caption2)
                            Text("\(String(format: "%.0f", diff.sdnn))ms").font(.caption2)
                            Text("\(String(format: "%.0f", diff.rmssd))ms").font(.caption2)
                            Text("\(String(format: "%.0f", diff.difference))ms").font(.caption2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 기분/운동/커피 상관관계

    private struct CorrelationRow: Identifiable {
        let id = UUID()
        // |r| — 정렬 기준. 비교할 데이터 자체가 부족한 항목은 맨 아래로 밀리게 -1을 준다.
        let strength: Double
        let text: String
        let isMissing: Bool
    }

    // 상관관계 강한 순으로 보여준다 — 기분/커피는 실제 Pearson r, 운동은 운동 여부(0/1)와
    // rMSSD의 점-이연 상관계수로 같은 기준(|r|)에 놓는다.
    private var correlationRows: [CorrelationRow] {
        guard let findings = viewModel.correlationFindings else { return [] }
        var rows: [CorrelationRow] = []

        if let r = findings.moodRMSSDCorrelation {
            rows.append(CorrelationRow(
                strength: abs(r),
                text: "기분 점수 상관계수 r = \(String(format: "%.2f", r)) (\(HRVStatistics.correlationStrengthLabel(r)))",
                isMissing: false
            ))
        } else {
            rows.append(CorrelationRow(strength: -1, text: "기분 상관관계: 같은 날짜의 기분·rMSSD 기록이 부족해요", isMissing: true))
        }

        if let r = findings.coffeeRMSSDCorrelation {
            rows.append(CorrelationRow(
                strength: abs(r),
                text: "커피 잔 수 상관계수 r = \(String(format: "%.2f", r)) (\(HRVStatistics.correlationStrengthLabel(r)))",
                isMissing: false
            ))
        } else {
            rows.append(CorrelationRow(strength: -1, text: "커피 상관관계: 같은 날짜의 커피·rMSSD 기록이 부족해요", isMissing: true))
        }

        if let r = findings.exerciseRMSSDCorrelation,
           let exerciseAvg = findings.exerciseDayAverageRMSSD,
           let restAvg = findings.restDayAverageRMSSD {
            rows.append(CorrelationRow(
                strength: abs(r),
                text: "운동한 날 평균 rMSSD \(String(format: "%.0f", exerciseAvg))ms · " +
                    "운동 안 한 날 평균 \(String(format: "%.0f", restAvg))ms (r = \(String(format: "%.2f", r)))",
                isMissing: false
            ))
        } else {
            rows.append(CorrelationRow(strength: -1, text: "운동 비교: 운동한 날과 안 한 날이 둘 다 있어야 비교할 수 있어요", isMissing: true))
        }

        return rows.sorted { $0.strength > $1.strength }
    }

    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("기분·운동·커피와 rMSSD 관계").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if viewModel.correlationFindings != nil {
                ForEach(correlationRows) { row in
                    Text(row.text)
                        .font(.footnote)
                        .foregroundStyle(row.isMissing ? .secondary : .primary)
                }
            } else {
                Text("해당 기간에 비교할 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// 수면/CV처럼 차트가 들어있는 섹션을 감싸는 카드 — vitalPanel(배경 Theme.primary50)과 달리
// 배경은 흰색, 테두리는 기본 색(Theme.systemGray5)을 쓴다.
private extension View {
    func panelCard() -> some View {
        self
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.systemGray5, lineWidth: 1))
            // 광원이 좌상단에 있다고 가정 — 그림자는 반대 방향인 우하단으로 옅게 떨어뜨린다.
            .shadow(color: .black.opacity(0.1), radius: 4, x: 2, y: 2)
    }
}

// 시작일/종료일을 각자 입력칸으로 나누는 대신, 하나의 입력(버튼)에 "시작일 ~ 종료일"을 같이
// 보여주고 탭하면 아래에서 시트 하나가 올라와 두 그래픽 캘린더를 연달아 고르게 한다 — 그래픽
// 캘린더는 각자 자유롭게 달을 넘길 수 있어서 시작일과 종료일이 서로 다른 달에 있어도 그대로
// 고를 수 있다. 화면에 있던 "분석" 버튼은 따로 두지 않고 이 시트 안으로 옮겨서, 기간을 다 고른
// 뒤 그 버튼 한 번으로 검색과 동시에 시트가 닫히게 한다.
private struct PeriodRangeRow: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    var maximumDate: Date?
    var isDisabled: Bool = false
    var onAnalyze: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
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
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                VStack {
                    // "시작일"/"종료일" 글자 라벨 없이, 두 compact 피커를 "~"로 이어서 하나의
                    // 입력처럼 보이게 한다. 시작일이 종료일보다 늦어질 수 없고, 종료일이 시작일보다
                    // 빨라질 수 없게 서로의 현재 값을 상대 피커의 in: 범위 경계로 넘긴다.
                    HStack(spacing: 8) {
                        datePicker(
                            for: $startDate,
                            title: "시작일",
                            range: Date.distantPast...min(endDate, maximumDate ?? .distantFuture)
                        )
                        Text("~").foregroundStyle(.secondary)
                        datePicker(
                            for: $endDate,
                            title: "종료일",
                            range: startDate...(maximumDate ?? .distantFuture)
                        )
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    // ui-style.md 버튼 크기 규칙의 Default(50pt).
                    Button {
                        isPresented = false
                        onAnalyze()
                    } label: {
                        Label("분석", systemImage: "waveform.path.ecg")
                            .font(Typography.cardTitle)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDisabled)
                    .padding()
                    .background(.bar)
                }
                .navigationTitle("분석 기간")
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(\.locale, Locale(identifier: "ko_KR"))
            // 날짜 입력 한 줄 + 분석 버튼뿐이라 내용에 딱 맞는 높이로 줄인다. compact 피커의 달력
            // 팝업은 시스템이 화면 안에 들어오게 알아서 위/아래로 뒤집어 띄우므로 시트가 낮아도 잘리지
            // 않는다.
            .presentationDetents([.height(230)])
        }
    }

    private func datePicker(for date: Binding<Date>, title: String, range: ClosedRange<Date>) -> some View {
        DatePicker(title, selection: date, in: range, displayedComponents: .date)
            .datePickerStyle(.compact)
            // 날짜에 따라 "7월 1일"/"12월 25일"처럼 표시 텍스트 길이가 달라져서 옆의 "~"와
            // 상대 피커가 좌우로 밀리는 걸 막는다 — 폭을 고정해서 어떤 날짜든 같은 자리에 보이게 한다.
            .frame(width: 130)
            .labelsHidden()
    }
}

#Preview {
    ReportView()
}
