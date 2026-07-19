import Charts
import SwiftUI

struct ReportView: View {
    @State private var viewModel = ReportViewModel()
    @State private var selectedSleepRange: SleepRange?

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
    @AxisMarkBuilder
    private static func dateAxisMarks(_ value: AxisValue) -> some AxisMark {
        AxisGridLine()
        AxisTick()
        AxisValueLabel {
            if let date = value.as(Date.self) {
                Text(HRVAnalysisView.monthDayFormatter.string(from: date))
            }
        }
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
                        sleepSection
                        cvSection
                        rmssdSection
                        sdnnRmssdSection
                        correlationSection
                    }
                }
                .padding()
            }
            .navigationTitle("보고서")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var datePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("분석 기간").font(.system(size: 13.6, weight: .semibold))
            IsoDateRow(title: "이전 진료일", date: $viewModel.previousVisitDate)
            IsoDateRow(title: "이번 진료일", date: $viewModel.thisVisitDate)
        }
    }

    private var analyzeButton: some View {
        Button {
            selectedSleepRange = nil
            Task { await viewModel.analyze() }
        } label: {
            Text("분석")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isAnalyzing)
    }

    // MARK: - 수면

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("수면").font(.system(size: 13.6, weight: .semibold))

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
                    y: .value("수면 시간", hours)
                )
                .foregroundStyle(Theme.sleep.opacity(selectedSleepRange?.id == range.id ? 1 : 0.7))
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
        .chartXAxis {
            AxisMarks { value in
                Self.dateAxisMarks(value)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
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

    // MARK: - 변동계수 (CV)

    private var cvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("변동계수 (CV)").font(.system(size: 13.6, weight: .semibold))

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
        .chartXAxis {
            AxisMarks { value in
                Self.dateAxisMarks(value)
            }
        }
    }

    // MARK: - rMSSD

    private var rmssdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rMSSD").font(.system(size: 13.6, weight: .semibold))

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

    // MARK: - SDNN vs rMSSD

    private var sdnnRmssdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SDNN vs rMSSD 차이 Top 3").font(.system(size: 13.6, weight: .semibold))

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

    private var correlationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("기분·운동·커피와 rMSSD 관계").font(.system(size: 13.6, weight: .semibold))

            if let findings = viewModel.correlationFindings {
                if let r = findings.moodRMSSDCorrelation {
                    Text("기분 점수 상관계수 r = \(String(format: "%.2f", r)) (\(HRVStatistics.correlationStrengthLabel(r)))")
                        .font(.footnote)
                } else {
                    Text("기분 상관관계: 같은 날짜의 기분·rMSSD 기록이 부족해요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let r = findings.coffeeRMSSDCorrelation {
                    Text("커피 잔 수 상관계수 r = \(String(format: "%.2f", r)) (\(HRVStatistics.correlationStrengthLabel(r)))")
                        .font(.footnote)
                } else {
                    Text("커피 상관관계: 같은 날짜의 커피·rMSSD 기록이 부족해요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let exerciseAvg = findings.exerciseDayAverageRMSSD, let restAvg = findings.restDayAverageRMSSD {
                    Text(
                        "운동한 날 평균 rMSSD \(String(format: "%.0f", exerciseAvg))ms · " +
                            "운동 안 한 날 평균 \(String(format: "%.0f", restAvg))ms"
                    )
                    .font(.footnote)
                } else {
                    Text("운동 비교: 운동한 날과 안 한 날이 둘 다 있어야 비교할 수 있어요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(ReportView.dateFormatter.string(from: date))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
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
