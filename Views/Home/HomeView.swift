import SwiftUI

struct HomeView: View {
    let refreshRequestID: UUID?
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = HomeViewModel()
    @State private var selectedDate = Date()

    init(refreshRequestID: UUID? = nil) {
        self.refreshRequestID = refreshRequestID
    }

    private static let briefingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // 선택한 날짜는 항상 사건 일자로 보여준다. 회복 지수는 계산할 수 있을 때만 해당 행을 추가한다.
    private var hasBriefingHeader: Bool {
        viewModel.briefingDate != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(selectedDate: $selectedDate)
                    .padding(.horizontal, 8)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        if hasBriefingHeader {
                            briefingHeader(score: viewModel.recoveryScore, date: viewModel.briefingDate)
                        }

                        briefingBody

                        if let errorMessage = viewModel.errorMessage {
                            inlineError(errorMessage)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("오늘의 수사 노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("오늘의 수사 노트")
                        .font(Typography.screenTitle)
                }
            }
        }
        // Apple Watch 동기화가 앱을 연 뒤 끝날 수 있어 브리핑은 홈에 들어올 때마다 갱신한다.
        // 기분·커피·복약은 각 IfNeeded 함수가 성공적으로 확인한 항목을 자체적으로 건너뛴다.
        .onAppear {
            Task { await viewModel.loadDailyBriefing(for: selectedDate, hrvTerm: authViewModel.hrvTerm) }
            Task { await viewModel.loadTodayMoodIfNeeded() }
            Task { await viewModel.loadTodayCoffeeCountIfNeeded() }
            Task { await viewModel.loadTodayMedicationLogsIfNeeded() }
        }
        .onChange(of: refreshRequestID) { _, requestID in
            guard requestID != nil else { return }
            Task { await viewModel.loadDailyBriefing(for: selectedDate, hrvTerm: authViewModel.hrvTerm) }
        }
        .onChange(of: selectedDate) { _, newDate in
            Task { await viewModel.loadDailyBriefing(for: newDate, hrvTerm: authViewModel.hrvTerm) }
        }
    }

    private func briefingHeader(score: RecoveryScore?, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let date {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    briefingHeaderLabel("사건 일자")

                    Text(Self.briefingDateFormatter.string(from: date))
                        .font(Typography.secondary)
                }
            }

            if let score {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    briefingHeaderLabel("회복 지수")

                    Text(String(score.value))
                        .font(Typography.sectionTitle.weight(.bold))

                    Text(score.label)
                        .font(Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
    }

    private func briefingHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(Theme.systemGray6, in: Capsule())
    }

    // recoveryScore/사건 일자와 별개로, "오늘 확보한 단서" 위에 전날 밤 수면시간·가장 최근 rMSSD를
    // 큰 글씨로 먼저 보여준다 — 둘 중 하나만 있어도(예: 전날 밤 수면 기록이 없어도 rMSSD는 있을 수
    // 있음) 그 값만 보이고, 둘 다 없으면 이 줄 자체를 그리지 않는다.
    private var hasSummaryStats: Bool {
        viewModel.previousNightSleepDuration != nil || viewModel.latestRMSSDValue != nil
    }

    private var summaryStatsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            summaryStat(
                title: "전날 수면시간",
                value: viewModel.previousNightSleepDuration.map(SleepAnalysisService.formattedDuration)
            )
            latestHRVStat
        }
    }

    private func summaryStat(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(Typography.sectionTitle.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 12))
    }

    private var latestHRVStat: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("가장 최근 HRV")
                .font(Typography.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(viewModel.latestRMSSDValue.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(Typography.sectionTitle.weight(.bold))
                if viewModel.latestRMSSDValue != nil {
                    Text("ms")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let comparison = viewModel.latestRMSSDComparison {
                let roundedDifference = Int(abs(comparison.difference).rounded())
                Text("\(comparison.difference >= 0 ? "↑" : "↓") \(roundedDifference)ms · \(comparison.status.label)")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 72, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 12))
    }

    private var briefingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasSummaryStats {
                summaryStatsRow
            }

            if !viewModel.todayBriefingClues.isEmpty {
                briefingSection(
                    title: "오늘 확보한 단서",
                    showsTopDivider: !hasSummaryStats
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.todayBriefingClues) { clue in
                            clueRow(clue.message)
                        }
                    }
                }
            }

            if !viewModel.dailySummaryHighlights.isEmpty {
                briefingSection(
                    title: "오늘의 신호",
                    showsTopDivider: !hasSummaryStats || !viewModel.todayBriefingClues.isEmpty
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.dailySummaryHighlights) { highlight in
                            highlightRow(highlight.message)
                        }
                    }
                }
            }

            // 오늘 확보한 단서·오늘의 신호가 둘 다 없으면(아직 분석할 근거가 부족하면) 빈 채로
            // 두지 않고 아직 조사 중이라는 걸 알려준다. 섹션 제목이 아니라 가운데 정렬된 상태
            // 문구라 briefingSection을 쓰지 않는다.
            if viewModel.todayBriefingClues.isEmpty && viewModel.dailySummaryHighlights.isEmpty {
                Text("수사중")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            }

            briefingSection(title: "수사 기록하기") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.hasCheckedMood && viewModel.todayMoodScore == nil {
                        moodPicker
                    }
                    if let moodErrorMessage = viewModel.moodErrorMessage {
                        inlineError(moodErrorMessage)
                    }

                    HStack(spacing: 16) {
                        coffeeButton
                        medicationButton(timing: .morning, isTaken: viewModel.hasMorningMedicationTaken)
                        medicationButton(timing: .bedtime, isTaken: viewModel.hasBedtimeMedicationTaken)
                    }
                    if let coffeeErrorMessage = viewModel.coffeeErrorMessage {
                        inlineError(coffeeErrorMessage)
                    }
                    if let medicationErrorMessage = viewModel.medicationErrorMessage {
                        inlineError(medicationErrorMessage)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 선(구분선) 위아래 간격이 같아 보이도록 위·아래 모두 20pt로 맞춘다. briefingBody 쪽에서
    // 추가 top padding을 주지 않아야 이 20pt가 이중으로 겹쳐 보이지 않는다.
    private func briefingSection<Content: View>(
        title: String,
        showsTopDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        // spacing을 0으로 두고 각 여백을 직접 지정한다 — VStack spacing과 padding이 겹쳐서
        // 선 아래쪽만 위쪽보다 더 떨어져 보이던 문제(spacing 10 + padding 20 = 30)를 막는다.
        VStack(alignment: .leading, spacing: 0) {
            if showsTopDivider {
                // 기본 Divider()보다 한 단계 진한 회색.
                Rectangle()
                    .fill(Theme.systemGray4)
                    .frame(height: 1)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            } else {
                Spacer()
                    .frame(height: 20)
            }

            Text(title)
                .font(Typography.body.weight(.bold))
                .foregroundStyle(Theme.primary800)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
    }

    private func clueRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.primary800)
            textWithBoldNumbers(message)
                .font(Typography.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 오늘의 신호 문구는 이미 문장 맨 앞에 구분되는 이모지가 있어, clueRow의 체크마크 아이콘을
    // 더하면 중복돼 보인다 — 그래서 아이콘 없이 텍스트만 보여준다.
    private func highlightRow(_ message: String) -> some View {
        Text(message)
            .font(Typography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func textWithBoldNumbers(_ value: String) -> Text {
        var result = Text("")
        var remaining = value.startIndex..<value.endIndex

        while let numberRange = value.range(
            of: #"\d+"#,
            options: .regularExpression,
            range: remaining
        ) {
            result = result + Text(String(value[remaining.lowerBound..<numberRange.lowerBound]))
            result = result + Text(String(value[numberRange])).bold()
            remaining = numberRange.upperBound..<value.endIndex
        }

        return result + Text(String(value[remaining]))
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moodPicker: some View {
        HStack(spacing: 16) {
            ForEach(MoodService.options, id: \.score) { option in
                Button {
                    Task { await viewModel.logMood(score: option.score) }
                } label: {
                    Text(option.emoji)
                        .font(.system(size: 32))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // 버튼 안 내용은 항상 한 줄(HStack) — ui-style.md "버튼 안에서는 줄바꿈하지 않는다".
    private var coffeeButton: some View {
        Button {
            Task { await viewModel.logCoffee() }
        } label: {
            Text("커피")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.primary, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if viewModel.todayCoffeeCount > 0 {
                        Text("\(viewModel.todayCoffeeCount)")
                            .font(.system(size: 9).bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.red, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
    }

    private func medicationButton(timing: MedicationTiming, isTaken: Bool) -> some View {
        Button {
            Task { await viewModel.logMedicationQuick(timing) }
        } label: {
            Text(timing.label)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.primary, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if isTaken {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                            .background(.white, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
        }
    }

}

#Preview {
    HomeView()
        .environment(AuthViewModel())
}
