import Charts
import SwiftUI

struct ReportView: View {
    @State private var viewModel = ReportViewModel()
    @State private var selectedSleepRange: SleepRange?

    private static let dateFormatter: DateFormatter = {
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
            DatePicker("이전 진료일", selection: $viewModel.previousVisitDate, displayedComponents: .date)
            DatePicker("이번 진료일", selection: $viewModel.thisVisitDate, displayedComponents: .date)
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
                SleepDetailPanel(sleepRange: selectedSleepRange)
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
    }

    // MARK: - rMSSD

    private var rmssdSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("rMSSD").font(.system(size: 13.6, weight: .semibold))

            if let findings = viewModel.rmssdFindings {
                if let lowestDate = findings.lowestDailyDate {
                    Text("가장 낮은 날: \(Self.dateFormatter.string(from: lowestDate))")
                        .font(.footnote)
                }
                if let lowestRaw = findings.lowestRawSample {
                    Text(
                        "가장 낮은 시각: \(Self.dateTimeFormatter.string(from: lowestRaw.date)) " +
                            "(\(String(format: "%.0f", lowestRaw.value))ms)"
                    )
                    .font(.footnote)
                }
                if let weekday = findings.lowestAverageWeekday, Self.weekdaySymbols.indices.contains(weekday - 1) {
                    Text("평균적으로 가장 낮은 요일: \(Self.weekdaySymbols[weekday - 1])")
                        .font(.footnote)
                }
            } else {
                Text("해당 기간에 rMSSD 데이터가 없어요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - SDNN vs rMSSD

    private var sdnnRmssdSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        VStack(alignment: .leading, spacing: 6) {
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

#Preview {
    ReportView()
}
