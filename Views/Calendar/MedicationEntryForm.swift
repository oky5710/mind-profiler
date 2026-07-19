import SwiftUI

// 약 등록(이름 + 복용 시간대)과 그날의 복용 체크(퀵버튼)를 한 화면에서 처리한다. mind-record 웹은
// 등록을 별도 "복용약 관리" 화면에서 하지만, iOS는 그 화면이 아직 없어서 여기 함께 넣었다 —
// 공공 약품 DB 검색(/drugs/search)은 범위 밖이라 이름만 직접 입력받는다.
struct MedicationEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var medications: [MedicationEntry] = []
    @State private var isLoadingMedications = true
    @State private var loadErrorMessage: String?

    @State private var newMedicationName = ""
    @State private var newMedicationTimings: Set<MedicationTiming> = []
    @State private var isAddingMedication = false
    @State private var addErrorMessage: String?

    @State private var selectedQuickTimings: Set<MedicationTiming> = []
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
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
                TextField("약 이름", text: $newMedicationName)
                ForEach(MedicationTiming.allCases) { timing in
                    Toggle(timing.label, isOn: timingBinding(timing, in: $newMedicationTimings))
                }
                if let addErrorMessage {
                    Text(addErrorMessage).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await addMedication() }
                } label: {
                    if isAddingMedication {
                        ProgressView()
                    } else {
                        Text("약 추가")
                    }
                }
                .disabled(isAddingMedication)
            }

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
        }
        .task { await loadMedications() }
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

    private func addMedication() async {
        addErrorMessage = nil
        let trimmedName = newMedicationName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            addErrorMessage = "약 이름을 입력해주세요."
            return
        }

        isAddingMedication = true
        do {
            try await MedicationService.addMedication(name: trimmedName, timings: Array(newMedicationTimings))
            newMedicationName = ""
            newMedicationTimings = []
            await loadMedications()
        } catch {
            addErrorMessage = error.localizedDescription
        }
        isAddingMedication = false
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
