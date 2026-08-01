import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let caseType = viewModel.briefingCaseType {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("사건명")
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                            Text(caseType.title)
                                .font(Typography.sectionTitle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.primary50)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if viewModel.hasCheckedMood && viewModel.todayMoodScore == nil {
                        moodPicker
                    }
                    if let moodErrorMessage = viewModel.moodErrorMessage {
                        Text(moodErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }

                    // 한 줄에 다 안 들어가면 버튼 내용을 줄이는 게 아니라 버튼째로 다음 줄로 내린다
                    // (ui-style.md "버튼 안에서는 줄바꿈하지 않는다").
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            coffeeButton
                            medicationButton(timing: .morning, icon: "🌅", isTaken: viewModel.hasMorningMedicationTaken)
                            medicationButton(timing: .bedtime, icon: "🌙", isTaken: viewModel.hasBedtimeMedicationTaken)
                        }
                        VStack(spacing: 8) {
                            coffeeButton
                            HStack(spacing: 12) {
                                medicationButton(timing: .morning, icon: "🌅", isTaken: viewModel.hasMorningMedicationTaken)
                                medicationButton(timing: .bedtime, icon: "🌙", isTaken: viewModel.hasBedtimeMedicationTaken)
                            }
                        }
                    }
                    if let coffeeErrorMessage = viewModel.coffeeErrorMessage {
                        Text(coffeeErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }
                    if let medicationErrorMessage = viewModel.medicationErrorMessage {
                        Text(medicationErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }
                }
                .padding()
            }
            .navigationTitle("오늘의 수사 노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("오늘의 수사 노트").font(Typography.screenTitle)
                }
            }
        }
        // 홈 탭에 들어올 때마다(onAppear) 다시 확인한다 — .task였다면 이 뷰가 처음 나타났을 때 딱
        // 한 번만 실행되고, 그때 네트워크 오류 등으로 실패하면 그 뒤로는 탭을 오가도 다시 시도되지
        // 않는다. 각 IfNeeded 함수가 이미 "성공적으로 확인함" 상태를 스스로 추적하므로, 매번 다시
        // 불러도 실제로 이미 성공한 항목은 그냥 바로 반환된다.
        .onAppear {
            Task { await viewModel.loadDailyBriefingIfNeeded() }
            Task { await viewModel.loadTodayMoodIfNeeded() }
            Task { await viewModel.loadTodayCoffeeCountIfNeeded() }
            Task { await viewModel.loadTodayMedicationLogsIfNeeded() }
        }
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
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.black.opacity(0.35), in: Capsule())
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
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.35), in: Capsule())
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
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.35), in: Capsule())
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
