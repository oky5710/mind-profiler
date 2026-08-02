import SwiftUI

struct HomeView: View {
    let refreshRequestID: UUID?
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

    // 헤더(Recovery/사건 일자)는 회복 점수나 사건명이 있을 때만 보인다.
    private var hasBriefingHeader: Bool {
        viewModel.briefingCaseType != nil || viewModel.recoveryScore != nil
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
            Task { await viewModel.loadDailyBriefing(for: selectedDate) }
            Task { await viewModel.loadTodayMoodIfNeeded() }
            Task { await viewModel.loadTodayCoffeeCountIfNeeded() }
            Task { await viewModel.loadTodayMedicationLogsIfNeeded() }
        }
        .onChange(of: refreshRequestID) { _, requestID in
            guard requestID != nil else { return }
            Task { await viewModel.loadDailyBriefing(for: selectedDate) }
        }
        .onChange(of: selectedDate) { _, newDate in
            Task { await viewModel.loadDailyBriefing(for: newDate) }
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

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                briefingHeaderLabel("회복 지수")

                Text(score.map { String($0.value) } ?? "—")
                    .font(Typography.sectionTitle.weight(.bold))

                if let score {
                    Text(score.label)
                        .font(Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }

    private func briefingHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(Theme.systemGray6, in: Capsule())
    }

    private var briefingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.todayBriefingClues.isEmpty {
                briefingSection(title: "오늘 확보한 단서", includesTopPadding: false) {
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
                    includesTopPadding: !viewModel.todayBriefingClues.isEmpty
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

            // 오늘 확보한 단서·오늘의 신호·수사중 플레이스홀더 중 하나는 항상 위에 오므로
            // 수사 기록하기가 첫 섹션이 되는 경우는 없다.
            briefingSection(title: "수사 기록하기", includesTopPadding: true) {
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
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func briefingSection<Content: View>(
        title: String,
        includesTopPadding: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 기본 Divider()보다 한 단계 진한 회색.
            Rectangle()
                .fill(Theme.systemGray4)
                .frame(height: 1)
                .padding(.top, includesTopPadding ? 20 : 12)

            Text(title)
                .font(Typography.body.weight(.bold))
                .foregroundStyle(Theme.primary800)
                .padding(.top, 12)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
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
}
