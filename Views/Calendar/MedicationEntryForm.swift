import SwiftUI

// 약 등록(식약처 낱알식별정보 검색으로 선택 + 복용 시간대)과 그날의 복용 체크(퀵버튼)를 한 화면에서
// 처리한다. mind-record 웹은 등록을 별도 "복용약 관리" 화면에서 하지만, iOS는 그 화면이 아직 없어서
// 여기 함께 넣었다.
struct MedicationEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var medications: [MedicationEntry] = []
    @State private var isLoadingMedications = true
    @State private var loadErrorMessage: String?
    @State private var isPresentingDrugSearch = false

    @State private var selectedQuickTimings: Set<MedicationTiming> = []
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
            Section("오늘 복용 처리") {
                ForEach(MedicationService.quickLogTimings) { timing in
                    Toggle(timing.label, isOn: timingBinding(timing, in: $selectedQuickTimings))
                }
                if let saveErrorMessage {
                    Text(saveErrorMessage).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await saveQuickLogs() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("저장")
                    }
                }
                .disabled(isSaving)
            }

            Section("등록된 약") {
                if isLoadingMedications {
                    ProgressView()
                } else if medications.isEmpty {
                    Text("등록된 약이 없어요. 아래에서 추가해보세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(medications) { medication in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name)
                            if !medication.timings.isEmpty {
                                Text(medication.timings.compactMap { MedicationTiming(rawValue: $0)?.label }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task { await removeMedications(at: offsets) }
                    }
                }
                if let loadErrorMessage {
                    Text(loadErrorMessage).font(.footnote).foregroundStyle(.red)
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
        .task { await loadMedications() }
        .sheet(isPresented: $isPresentingDrugSearch) {
            DrugSearchSheet(existingItemSeqs: Set(medications.compactMap(\.itemSeq))) {
                await loadMedications()
            }
        }
    }

    private func timingBinding(_ timing: MedicationTiming, in set: Binding<Set<MedicationTiming>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(timing) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(timing) } else { set.wrappedValue.remove(timing) }
            }
        )
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

    private func saveQuickLogs() async {
        saveErrorMessage = nil
        guard !selectedQuickTimings.isEmpty else {
            saveErrorMessage = "하나 이상 선택해주세요."
            return
        }

        isSaving = true
        do {
            for timing in MedicationService.quickLogTimings where selectedQuickTimings.contains(timing) {
                try await MedicationService.logTiming(timing, date: date)
            }
            await onSaved()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
