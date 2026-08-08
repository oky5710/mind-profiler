import SwiftUI

struct HomeView: View {
    let refreshRequestID: UUID?
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(PatternNavigationCenter.self) private var patternNavigationCenter
    @State private var viewModel = HomeViewModel()
    @State private var selectedDate = Date()
    // 오늘 날짜에 표시할 데이터가 전혀 없으면(수면 기록이 아예 없어 회복 지수도 못 구하는 등) 빈
    // 화면 대신 전날 것을 기본으로 보여준다 — 최초 진입 시 한 번만 시도하고, 그 뒤 사용자가 직접
    // 고른 날짜에는 적용하지 않는다.
    @State private var hasAutoFallenBackToPreviousDay = false
    @State private var isShowingRecoveryScoreInfo = false

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

    // 오늘 날짜로 처음 열었는데 보여줄 게 전혀 없으면(수면 기록이 아예 없어 회복 지수도 못 구하는
    // 경우 등) 빈 화면 대신 전날 것을 기본으로 보여준다. recoveryScore·사건 일자뿐 아니라 요약
    // 카드(최근 HRV 등)·오늘 확보한 단서·오늘의 신호까지 전부 비었을 때만 넘어간다 — 이 중 하나라도
    // 있으면 오늘 볼 게 있다는 뜻이라 넘어가면 안 된다. 최초 진입 시 한 번만 시도하고, 이후
    // 사용자가 직접 고른 날짜에는 있는 그대로(빈 상태 포함) 보여준다.
    private func fallBackToPreviousDayIfNeeded() {
        guard !hasAutoFallenBackToPreviousDay,
              Calendar.current.isDateInToday(selectedDate),
              viewModel.recoveryScore == nil,
              viewModel.briefingCaseType == nil,
              !hasSummaryStats,
              viewModel.todayBriefingClues.isEmpty,
              viewModel.dailySummaryHighlights.isEmpty,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)
        else { return }
        hasAutoFallenBackToPreviousDay = true
        selectedDate = yesterday
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
                        .lineLimit(1)
                }
            }
        }
        // Apple Watch 동기화가 앱을 연 뒤 끝날 수 있어 브리핑은 홈에 들어올 때마다 갱신한다.
        // 기분·커피·복약은 각 IfNeeded 함수가 성공적으로 확인한 항목을 자체적으로 건너뛴다.
        .onAppear {
            Task {
                await viewModel.loadDailyBriefing(for: selectedDate, hrvTerm: authViewModel.hrvTerm)
                fallBackToPreviousDayIfNeeded()
            }
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
                        .font(Typography.screenTitle)

                    Text(score.label)
                        .font(Typography.secondary)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        isShowingRecoveryScoreInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .padding(.horizontal, 24)
        .sheet(isPresented: $isShowingRecoveryScoreInfo) {
            RecoveryScoreInfoView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func briefingHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(Theme.systemGray6, in: Capsule())
    }

    // recoveryScore/사건 일자와 별개로, "오늘 확보한 단서" 위에 전날 밤 수면시간·최근 rMSSD를
    // 큰 글씨로 먼저 보여준다 — 둘 중 하나만 있어도(예: 전날 밤 수면 기록이 없어도 rMSSD는 있을 수
    // 있음) 그 값만 보이고, 둘 다 없으면 이 줄 자체를 그리지 않는다.
    private var hasSummaryStats: Bool {
        viewModel.previousNightSleepDuration != nil || viewModel.latestRMSSDValue != nil
    }

    private var summaryStatsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            previousNightSleepStat
            latestHRVStat
        }
    }

    private var previousNightSleepStat: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("전날 수면시간")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 값(시간/분)과 화살표 이후 비교문구는 각각 한 줄로 붙어 있어야 하지만, 둘을 나란히
            // 놓을 자리가 없으면 비교문구를 통째로 다음 줄로 내린다 — 최근 HRV 카드와 같은 패턴.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 6) {
                    previousNightSleepValue
                    previousNightSleepComparison
                }
                VStack(alignment: .leading, spacing: 4) {
                    previousNightSleepValue
                    previousNightSleepComparison
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: viewModel.briefingDate ?? selectedDate)
            let previousNight = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            patternNavigationCenter.requestSleepView(for: previousNight)
        }
    }

    private var previousNightSleepValue: some View {
        let totalMinutes = viewModel.previousNightSleepDuration.map { Int($0) / 60 }
        let hours = totalMinutes.map { $0 / 60 }
        let minutes = totalMinutes.map { $0 % 60 }

        return Group {
            if let hours, let minutes {
                // 숫자만 크게, "시간"/"분" 단위 글자는 작게 — 최근 HRV 카드의 값+단위(ms)와
                // 같은 위계를 시간·분 두 쌍 모두에 적용한다.
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(hours)")
                        .font(Typography.screenTitle)
                        .lineLimit(1)
                    Text("시간")
                        .font(Typography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(minutes)")
                        .font(Typography.screenTitle)
                        .lineLimit(1)
                    Text("분")
                        .font(Typography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(Typography.screenTitle)
            }
        }
    }

    @ViewBuilder
    private var previousNightSleepComparison: some View {
        if let difference = viewModel.previousNightSleepDurationDifferenceMinutes {
            comparisonText(isHigher: difference >= 0, detail: "\(Int(abs(difference).rounded()))분")
        }
    }

    // 화살표만 방향에 따라 색을 준다 — 높음(초록)/낮음(빨강, 눈을 덜 아프게 절반쯽 밝기). 나머지
    // 수치·문구는 계속 회색으로 둬서 화살표 색만 눈에 띄게 한다.
    private func comparisonText(isHigher: Bool, detail: String) -> some View {
        HStack(spacing: 2) {
            Text(isHigher ? "↑" : "↓")
                .foregroundStyle(isHigher ? Theme.systemGreen : Theme.systemRed.opacity(0.6))
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .font(Typography.caption)
        .lineLimit(1)
    }

    private var latestHRVStat: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("최근 HRV")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // 값+단위, 화살표+비교문구는 각각 한 줄로 붙어 있어야 하지만, 둘을 나란히 놓을 자리가
            // 없으면(좁은 화면·큰 텍스트 크기) 억지로 압축해 줄바꿈시키는 대신 비교문구를 통째로
            // 아래 줄로 내린다 — ViewThatFits가 가로로 안 맞으면 두 번째(세로) 후보를 고른다.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 6) {
                    latestHRVValue
                    latestHRVComparison
                }
                VStack(alignment: .leading, spacing: 4) {
                    latestHRVValue
                    latestHRVComparison
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Theme.systemGray6, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            patternNavigationCenter.requestHRVTrendView()
        }
    }

    private var latestHRVValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(viewModel.latestRMSSDValue.map { "\(Int($0.rounded()))" } ?? "—")
                .font(Typography.screenTitle)
                .lineLimit(1)
            if viewModel.latestRMSSDValue != nil {
                Text("ms")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var latestHRVComparison: some View {
        if let comparison = viewModel.latestRMSSDComparison {
            let roundedDifference = Int(abs(comparison.difference).rounded())
            comparisonText(
                isHigher: comparison.difference >= 0,
                detail: "\(roundedDifference)ms · \(comparison.status.label)"
            )
        }
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
                VStack(spacing: 6) {
                    Image("InvestigatingIllustration")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 121)
                    Text("수사중")
                        .font(Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
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
                        if viewModel.hasMorningMedicationRegistered {
                            medicationButton(timing: .morning, isTaken: viewModel.hasMorningMedicationTaken)
                        }
                        if viewModel.hasBedtimeMedicationRegistered {
                            medicationButton(timing: .bedtime, isTaken: viewModel.hasBedtimeMedicationTaken)
                        }
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
                .font(Typography.cardTitle)
                .foregroundStyle(Theme.primary800)
                .lineLimit(1)

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
                .font(Typography.secondary)
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
            .font(Typography.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func textWithBoldNumbers(_ value: String) -> Text {
        var result = Text("")
        var remaining = value.startIndex..<value.endIndex

        // "14:32" 같은 시각은 \d+만으로 매칭하면 ":" 앞뒤로 서로 다른 Text 런(런 경계)으로
        // 쪼개져, 공백이 없는 자리에서도 줄바꿈이 일어날 수 있다 — 시:분을 하나의 매칭으로 묶어
        // 한 Text 런으로 유지한다.
        while let numberRange = value.range(
            of: #"\d+(?::\d+)?"#,
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
        VStack(spacing: 8) {
            Text("오늘의 기분은?")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

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
                            .background(Theme.systemRed, in: Circle())
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

private struct RecoveryScoreInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("회복지수는 절대적인 건강 점수가 아닙니다.")
                    Text("최근 30일 동안의 나의 데이터를 기준으로 오늘이 평소보다 얼마나 회복되었는지를 보여주는 개인화된 지표입니다.")
                    Text("계산 과정은 다음과 같습니다.")

                    VStack(alignment: .leading, spacing: 6) {
                        bullet("수면, 오전, 오후로 시간을 구분합니다.")
                        bullet("각 시간대에서 최근 30일 rMSSD 중앙값과 오늘의 중앙값을 비교합니다.")
                        bullet("MAD(Median Absolute Deviation)를 이용하여 평소와의 차이를 계산합니다.")
                        bullet("각 시간대의 결과를 통합하여 회복지수를 계산합니다.")
                    }

                    Text("회복지수는 다른 사람과 비교하기 위한 점수가 아니라 자신의 평소 상태와 비교하기 위한 점수입니다.")
                }
                .font(Typography.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .navigationTitle("회복지수는 어떻게 계산되나요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthViewModel())
        .environment(PatternNavigationCenter())
}
