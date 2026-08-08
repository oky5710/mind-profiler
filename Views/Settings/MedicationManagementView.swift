import SwiftUI

// 약 등록 전용 화면 — mind-record 웹의 별도 "복용약 관리" 화면(MedicinePage.tsx)에 대응한다.
// 등록은 날짜와 무관한 전역 작업이라 설정 메뉴 아래로 옮겼고, 그날그날의 복용 체크(퀵버튼)는
// 캘린더의 MedicationEntryForm에 남는다.
struct MedicationManagementView: View {
    @State private var medications: [MedicationEntry] = []
    @State private var isLoadingMedications = true
    @State private var loadErrorMessage: String?
    @State private var isPresentingDrugSearch = false

    var body: some View {
        List {
            Section("등록된 약") {
                if isLoadingMedications {
                    ProgressView()
                } else if medications.isEmpty {
                    Text("등록된 약이 없어요. 아래에서 추가해보세요.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(medications) { medication in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name)
                            if !medication.timings.isEmpty {
                                Text(medication.timings.compactMap { MedicationTiming(rawValue: $0)?.label }.joined(separator: ", "))
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task { await removeMedications(at: offsets) }
                    }
                }
                if let loadErrorMessage {
                    Text(loadErrorMessage).font(Typography.caption).foregroundStyle(.red)
                }
            }

            Section("새 약 등록") {
                Button {
                    isPresentingDrugSearch = true
                } label: {
                    Label("약 검색으로 추가", systemImage: "magnifyingglass")
                }
            }
        }
        .navigationTitle("약 등록")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMedications() }
        .sheet(isPresented: $isPresentingDrugSearch) {
            DrugSearchSheet(existingItemSeqs: Set(medications.compactMap(\.itemSeq))) {
                await loadMedications()
            }
        }
    }

    private func loadMedications() async {
        isLoadingMedications = true
        do {
            medications = try await MedicationService.allMedications()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoadingMedications = false
    }

    private func removeMedications(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await MedicationService.removeMedication(id: medications[index].id)
            } catch {
                loadErrorMessage = error.localizedDescription
            }
        }
        await loadMedications()
    }
}

#Preview {
    NavigationStack {
        MedicationManagementView()
    }
}
