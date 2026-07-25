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

    // 수면/CV 차트가 같은 domain을 쓰더라도 각자 자동(automatic) 눈금에 맡기면 마크 종류(Bar vs
    // Area+Line)에 따라 서로 다른 위치에 눈금이 생길 수 있다(ui-style.md "x축 눈금 위치는 반드시
    // 동일해야 한다") — 두 차트가 공유하는 눈금 Date 배열을 직접 계산해서 .chartXAxis에 동일하게 적용한다.
    private var dateAxisTickDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: viewModel.previousVisitDate)
        let end = calendar.startOfDay(for: viewModel.thisVisitDate)
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
                VStack(alignment: .leading, spacing: 24) {
                    datePickers
                    analyzeButton

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

    private var datePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("분석 기간").font(Typography.sectionTitle)
                .padding(.bottom, 8)
            HStack(spacing: 12) {
                IsoDateRow(title: "시작일", date: $viewModel.previousVisitDate)
                IsoDateRow(title: "종료일", date: $viewModel.thisVisitDate)
            }
        }
    }

    private var analyzeButton: some View {
        Button {
            selectedSleepRange = nil
            Task { await viewModel.analyze() }
        } label: {
            Label("분석", systemImage: "waveform.path.ecg")
                .font(Typography.button)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isAnalyzing)
    }

    // MARK: - 기간 요약 (심박수/SDNN/rMSSD 중앙값)

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("기간 요약").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if let vitals = viewModel.vitalMedians,
               vitals.restingHeartRate != nil || vitals.sdnn != nil || vitals.rmssd != nil {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("안정시 심박수 중앙값").font(.footnote).foregroundStyle(.secondary)
                        Text(vitals.restingHeartRate.map { "\(Int($0.rounded()))bpm" } ?? "—").font(.footnote)
                    }
                    GridRow {
                        Text("SDNN 중앙값").font(.footnote).foregroundStyle(.secondary)
                        Text(vitals.sdnn.map { "\(Int($0.rounded()))ms" } ?? "—").font(.footnote)
                    }
                    GridRow {
                        Text("rMSSD 중앙값").font(.footnote).foregroundStyle(.secondary)
                        Text(vitals.rmssd.map { "\(Int($0.rounded()))ms" } ?? "—").font(.footnote)
                    }
                }
            } else {
                Text("해당 기간에 심박수/HRV 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 수면

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("수면").font(Typography.sectionTitle)
                .padding(.bottom, 8)

            if let avgDuration = viewModel.averageSleepDuration, let avgScore = viewModel.averageSleepScore {
                Text("평균 수면 시간 \(SleepAnalysisService.formattedDuration(avgDuration)) · 평균 점수 \(Int(avgScore.rounded()))점")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        // 아래 CV 차트와 같은 도메인을 명시해야 두 차트의 x축 눈금 위치가 일치한다 — 각자 자기
        // 데이터 범위로 도메인을 추론하게 두면(수면 없는 날/CV 없는 날이 있을 때) 눈금이 어긋난다.
        .chartXScale(domain: viewModel.previousVisitDate...viewModel.thisVisitDate)
        .chartXAxis {
            AxisMarks(values: dateAxisTickDates) { value in
                Self.dateAxisMarks(value)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack {
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

    private var sleepChartDayCount: Int {
        let dates = viewModel.sleepRanges.map(\.start)
        guard let minDate = dates.min(), let maxDate = dates.max() else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: minDate, to: maxDate).day ?? 0
        return max(days + 1, 1)
    }

    private func updateSleepBarWidth(plotWidth: CGFloat) {
        let bandwidth = plotWidth / CGFloat(sleepChartDayCount)
        sleepBarWidth = (bandwidth * 0.6).clamped(to: 10...30)
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
        // 위 수면 차트와 같은 도메인 — 두 차트가 같은 x축 눈금을 공유하게 한다.
        .chartXScale(domain: viewModel.previousVisitDate...viewModel.thisVisitDate)
        .chartXAxis {
            AxisMarks(values: dateAxisTickDates) { value in
                Self.dateAxisMarks(value)
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

// DatePicker는 커스텀 날짜 포맷 문자열을 직접 받지 않고 로케일의 기본 형식을 따른다 — 로케일을
// sv_SE 같은 걸로 바꿔 yyyy-MM-dd를 얻는 우회법은 한국어 UI(요일/버튼 등)까지 같이 깨진다. 그 대신
// 표시는 직접 포맷한 텍스트로 하고, 탭하면 한국어 로케일 그래픽 피커를 시트로 띄운다.
private struct IsoDateRow: View {
    let title: String
    @Binding var date: Date
    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.secondary)
                .foregroundStyle(.secondary)
            Button {
                isPresented = true
            } label: {
                Text(ReportView.dateFormatter.string(from: date))
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Theme.systemGray5, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                DatePicker(title, selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { isPresented = false }
                        }
                    }
            }
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    ReportView()
}
