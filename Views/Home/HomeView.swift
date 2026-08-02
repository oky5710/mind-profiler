import SwiftUI

struct HomeView: View {
    let refreshRequestID: UUID?
    @State private var viewModel = HomeViewModel()

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.briefingCaseType != nil || viewModel.recoveryScore != nil {
                        VStack(spacing: 0) {
                            briefingHeader(score: viewModel.recoveryScore, date: viewModel.briefingDate)
                            briefingBody
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("수사 기록하기")
                            .font(Typography.body.weight(.bold))
                            .foregroundStyle(Theme.primary800)

                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.hasCheckedMood && viewModel.todayMoodScore == nil {
                                moodPicker
                            }
                            if let moodErrorMessage = viewModel.moodErrorMessage {
                                inlineError(moodErrorMessage)
                            }

                            HStack(spacing: 16) {
                                coffeeButton
                                medicationButton(timing: .morning, icon: "🌅", isTaken: viewModel.hasMorningMedicationTaken)
                                medicationButton(timing: .bedtime, icon: "🌙", isTaken: viewModel.hasBedtimeMedicationTaken)
                            }
                            if let coffeeErrorMessage = viewModel.coffeeErrorMessage {
                                inlineError(coffeeErrorMessage)
                            }
                            if let medicationErrorMessage = viewModel.medicationErrorMessage {
                                inlineError(medicationErrorMessage)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .investigationCard()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                    if let errorMessage = viewModel.errorMessage {
                        inlineError(errorMessage)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom)
            }
            .background(Theme.primary.ignoresSafeArea())
            .navigationTitle("오늘의 수사 노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("오늘의 수사 노트")
                        .font(Typography.screenTitle)
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(Theme.primary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Apple Watch 동기화가 앱을 연 뒤 끝날 수 있어 브리핑은 홈에 들어올 때마다 갱신한다.
        // 기분·커피·복약은 각 IfNeeded 함수가 성공적으로 확인한 항목을 자체적으로 건너뛴다.
        .onAppear {
            Task { await viewModel.loadDailyBriefing() }
            Task { await viewModel.loadTodayMoodIfNeeded() }
            Task { await viewModel.loadTodayCoffeeCountIfNeeded() }
            Task { await viewModel.loadTodayMedicationLogsIfNeeded() }
        }
        .onChange(of: refreshRequestID) { _, requestID in
            guard requestID != nil else { return }
            Task { await viewModel.loadDailyBriefing() }
        }
    }

    private func briefingHeader(score: RecoveryScore?, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                briefingHeaderLabel("Recovery")

                Text(score.map { String($0.value) } ?? "—")
                    .font(Typography.sectionTitle.weight(.bold))
                    .foregroundStyle(.white)

                if let score {
                    Text(score.label)
                        .font(Typography.secondary)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if let date {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    briefingHeaderLabel("사건 일자")

                    Text(Self.briefingDateFormatter.string(from: date))
                        .font(Typography.secondary)
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.horizontal, 20)
        // 본문이 36pt 겹쳐도 사건 일자가 가려지지 않도록 같은 높이를 확보한다.
        .padding(.bottom, 56)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.primary, location: 0),
                    .init(color: Theme.primary, location: 0.25),
                    .init(color: Theme.primary700, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func briefingHeaderLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
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

            briefingSection(
                title: "어제 확보한 단서",
                includesTopPadding: !viewModel.todayBriefingClues.isEmpty
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.briefingClues.isEmpty {
                        clueRow("평소와 크게 다른 단서는 발견되지 않았어요.")
                    } else {
                        ForEach(viewModel.briefingClues) { clue in
                            clueRow(clue.message)
                        }
                    }
                }
            }

        }
        // 본문을 헤더 위로 36pt 올리고, 겹친 만큼 상단 내부 여백을 더해
        // 첫 섹션의 실제 위치는 유지한다. 둥근 모서리 바깥에는 헤더 색이 보인다.
        .padding(.top, 36)
        .padding(.horizontal, 24)
        .background(
            Color.white,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 36,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 36
            )
        )
        .padding(.top, -36)
    }

    private func briefingSection<Content: View>(
        title: String,
        includesTopPadding: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Typography.body.weight(.bold))
                .foregroundStyle(Theme.primary800)
                .padding(.top, includesTopPadding ? 16 : 0)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .investigationCard()
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
            HStack(spacing: 4) {
                Text("☕").font(.system(size: 16))
                Text("커피").font(.caption).foregroundStyle(.white)
            }
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

    private func medicationButton(timing: MedicationTiming, icon: String, isTaken: Bool) -> some View {
        Button {
            Task { await viewModel.logMedicationQuick(timing) }
        } label: {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: 16))
                Text(timing.label).font(.caption).foregroundStyle(.white)
            }
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
