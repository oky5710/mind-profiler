import SwiftUI

// 원래 HomeView의 "장기 미제 사건" 섹션 — 설정 메뉴 항목으로 옮겨왔다. 부모(SettingsView)가 이미
// NavigationStack이라 여기서 새로 만들지 않는다.
struct UnsolvedCasesView: View {
    @State private var viewModel = UnsolvedCasesViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoadingUnsolvedCases && viewModel.unsolvedCaseResults.isEmpty {
                    ProgressView("최근 90일의 증거를 분석하는 중...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ForEach(Array(viewModel.unsolvedCaseResults.enumerated()), id: \.element.id) { index, result in
                        HStack(alignment: .top, spacing: 10) {
                            Text(result.type.icon)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.type.title)
                                    .font(Typography.body.weight(.semibold))
                                    .foregroundStyle(Theme.primary800)
                                Text(result.summary)
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)

                                if let insight = result.insight {
                                    Divider()
                                        .padding(.vertical, 6)
                                    Text(insight.title)
                                        .font(Typography.body.weight(.bold))
                                        .foregroundStyle(Theme.primary800)
                                    Text(insight.summary)
                                        .font(Typography.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(insight.evidence)
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(CaseInsight.caution)
                                        .font(Typography.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)

                        if index < viewModel.unsolvedCaseResults.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .investigationCard()
            .padding(16)
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .navigationTitle("장기 미제 사건")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await viewModel.loadUnsolvedCasesIfNeeded() }
        }
    }
}

#Preview {
    NavigationStack {
        UnsolvedCasesView()
    }
}
