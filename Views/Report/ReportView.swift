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
                        rmssdLowestFindingsSection
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
                    vitalPanel(title: "안정시 심박수", value: vitals.restingHeartRate.map { "\(Int($0.rounded()))" }, unit: "bpm")
                    vitalPanel(title: "rMSSD", value: vitals.rmssd.map { "\(Int($0.rounded()))" }, unit: "ms")
                    vitalPanel(title: "SDNN", value: vitals.sdnn.map { "\(Int($0.rounded()))" }, unit: "ms")
                }
            } else {
                Text("해당 기간에 심박수/HRV 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // value를 String으로 받는 이유는, 숫자+단위(bpm/ms)뿐 아니라 요일("화요일")·시간대("3시~4시")
    // 처럼 이미 포맷된 문자열도 같은 카드 스타일로 보여줘야 해서다.
    private func vitalPanel(title: String, value: String?, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value ?? "—")
                    .font(.system(size: 28, weight: .bold))
                if value != nil, let unit {
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
        .shadow(color: .black.opacity(0.1), radius: 3, x: 1, y: 1)
    }

    // vitalPanel과 같은 "작은 라벨 + 큰 굵은 값" 조합이지만, 이미 panelCard로 감싸인 섹션
    // 안에서 쓰는 용도라 테두리/그림자는 따로 두지 않고 배경(Theme.primary50)만 준다. value를
    // 문자열이 아니라 Text로 받는 이유는, 평균 수면 시간처럼 "N시간 M분"에서 숫자는 크게·단위
    // (시간/분)는 작게 섞어서 조합해야 하는 경우가 있어서다(durationText 참고) — Text는 +로
    // 이어붙여도 조각별 폰트가 유지된다.
    private func bigStat(title: String, value: Text, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 8))
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
                HStack(spacing: 10) {
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
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        return hour < 10 ? (calendar.date(byAdding: .day, value: -1, to: day) ?? day) : day
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

    private struct SleepBar: Identifiable {
        let range: SleepRange
        let label: Date
        var id: UUID { range.id }
    }

    private var sleepBars: [SleepBar] {
        viewModel.sleepRanges.map { SleepBar(range: $0, label: nightLabel(for: $0.start)) }
    }

    // 세로축 눈금(0~24)을 실제 시각으로 바꾼다 — 0은 10시, 24는 다음날 10시.
    private func clockLabel(forHour hour: Double) -> String {
        "\((10 + Int(hour.rounded(.down))) % 24)"
    }

    private static let sleepYAxisTicks: [Double] = [0, 6, 12, 18, 24]

    private var sleepBarChart: some View {
        Chart {
            ForEach(sleepBars) { bar in
                let yRange = sleepBarYRange(for: bar.range, nightLabel: bar.label)
                BarMark(
                    x: .value("날짜", bar.label, unit: .day),
                    yStart: .value("잠든 시각", yRange.lowerBound),
                    yEnd: .value("일어난 시각", yRange.upperBound),
                    width: .fixed(sleepBarWidth)
                )
                .foregroundStyle(Theme.sleep.opacity(0.7))
                .cornerRadius(4)
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
                            let sameDayBars = sleepBars.filter {
                                calendar.isDate($0.label, inSameDayAs: tappedDate)
                            }
                            // 같은 날짜에 세션이 여러 개면(예: 이른 아침에 잠깐 더 잔 것 + 그날
                            // 밤잠) 탭한 세로 위치와 가장 가까운 세션을 고른다 — x만으로는 그날
                            // 중 어느 세션인지 구분이 안 된다.
                            if let tappedHour: Double = proxy.value(atY: localY) {
                                selectedSleepRange = sameDayBars.min {
                                    distance(from: tappedHour, to: sleepBarYRange(for: $0.range, nightLabel: $0.label)) <
                                        distance(from: tappedHour, to: sleepBarYRange(for: $1.range, nightLabel: $1.label))
                                }?.range
                            } else {
                                selectedSleepRange = sameDayBars.first?.range
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
        if let bar = sleepBars.first(where: { $0.range.id == range.id }) {
            let yRange = sleepBarYRange(for: bar.range, nightLabel: bar.label)
            if let plotFrame = proxy.plotFrame,
               let x = proxy.position(forX: dayMidpoint(of: bar.label)),
               let yTop = proxy.position(forY: yRange.upperBound),
               let yBottom = proxy.position(forY: yRange.lowerBound) {
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
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)

                    Text(label(value))
                        .font(.system(size: 9))
                        .tracking(1)
                        .padding(.horizontal, 3)
                        .background(Color(.systemBackground).opacity(0.85))
                        .position(x: plotRect.minX + 16, y: plotRect.minY + y)
                }
            }
        }
    }

    // MARK: - 변동계수 (CV)

    private var cvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("변동계수 (CV)").font(Typography.sectionTitle)
                if let findings = viewModel.cvFindings {
                    averageCVChip(findings.overallCV)
                }
            }
            .padding(.bottom, 8)

            if let findings = viewModel.cvFindings {
                cvChart(findings)
            } else {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    // design-system.md Chip 스펙(15pt Medium) — 전체 기간 CV를 제목 옆에 짧게 보여준다.
    private func averageCVChip(_ value: Double) -> some View {
        Text("평균 \(String(format: "%.1f", value))%")
            .font(.system(size: 15, weight: .medium))
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
                }
            }
        }
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
            Text("rMSSD 낮은 날 Top \(viewModel.rmssdLowestDayRows.count)").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if viewModel.rmssdLowestDayRows.isEmpty {
                Text("해당 기간에 비교할 데이터가 없어요")
                    .font(.footnote)
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
                .font(.caption.bold())

            HStack(alignment: .top, spacing: 12) {
                lowestDayChip(
                    label: "rMSSD",
                    value: Text("\(Int(row.rmssd.rounded()))")
                        .font(.system(size: 20, weight: .bold))
                        + Text("ms").font(.caption2).fontWeight(.regular),
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
                .font(.caption2.bold())
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.caption2.bold())
        }
    }

    // 스케줄 — 라벨과 값을 옆으로 붙이지 않고 줄바꿈해서 위/아래로 둔다(스케줄 여러 개가
    // 길게 이어질 수 있어서 한 줄에 라벨과 나란히 두면 좁아 보인다).
    private func lowestDayDetailLine(label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.caption2)
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
                    tableRowDivider

                    ForEach(viewModel.topSDNNRMSSDDifferences) { diff in
                        GridRow {
                            Text(Self.dateTimeFormatter.string(from: diff.date)).font(.caption2)
                            Text("\(String(format: "%.0f", diff.sdnn))ms").font(.caption2)
                            Text("\(String(format: "%.0f", diff.rmssd))ms").font(.caption2)
                            Text("\(String(format: "%.0f", diff.difference))ms").font(.caption2)
                        }
                        tableRowDivider
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelCard()
    }

    // Grid 안에서 GridRow로 감싸지 않고 바로 두면 그 한 줄이 되고, gridCellColumns(4)로 4칸을
    // 전부 차지하게 해서 표 너비 전체를 가로지르는 구분선이 된다.
    private var tableRowDivider: some View {
        Rectangle()
            .fill(Theme.systemGray5)
            .frame(height: 1)
            .gridCellColumns(4)
    }

    // MARK: - 상관계수

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
                text: "전날 운동한 날 평균 rMSSD \(String(format: "%.0f", exerciseAvg))ms · " +
                    "전날 운동 안 한 날 평균 \(String(format: "%.0f", restAvg))ms (r = \(String(format: "%.2f", r)))",
                isMissing: false
            ))
        } else {
            rows.append(CorrelationRow(strength: -1, text: "전날 운동 비교: 전날 운동한 날과 안 한 날이 둘 다 있어야 비교할 수 있어요", isMissing: true))
        }

        if let r = findings.sleepDurationRMSSDCorrelation {
            rows.append(CorrelationRow(
                strength: abs(r),
                text: "전날 수면시간 상관계수 r = \(String(format: "%.2f", r)) (\(HRVStatistics.correlationStrengthLabel(r)))",
                isMissing: false
            ))
        } else {
            rows.append(CorrelationRow(strength: -1, text: "전날 수면시간 상관관계: 전날 밤 수면·그날 rMSSD 기록이 부족해요", isMissing: true))
        }

        return rows.sorted { $0.strength > $1.strength }
    }

    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("상관계수").font(Typography.sectionTitle)
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
        .panelCard()
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
            // 광원이 좌상단에 있다고 가정 — 그림자는 반대 방향인 우하단으로 옅게 떨어뜨린다.
            .shadow(color: .black.opacity(0.1), radius: 3, x: 1, y: 1)
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
