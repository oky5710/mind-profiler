import SwiftUI

// 캘린더 날짜 요약 시트의 연필 아이콘으로 들어오는 수정 화면 — 복용 기록 자체(누가/언제 눌렀는지)는
// 바꿀 게 없고, 잘못 고른 시간대(아침/점심/저녁/취침전/필요시)만 바로잡는 용도라 다른 입력 폼처럼
// 크지 않다.
struct MedicationLogEditForm: View {
    let entry: MedicationLogEntry
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTiming: MedicationTiming
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entry: MedicationLogEntry, onSaved: @escaping () async -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        self._selectedTiming = State(initialValue: entry.timing.flatMap(MedicationTiming.init(rawValue:)) ?? .morning)
    }

    var body: some View {
        Form {
            Section(entry.medication?.name ?? "약") {
                Picker("시간대", selection: $selectedTiming) {
                    ForEach(MedicationTiming.allCases) { timing in
                        Text(timing.label).tag(timing)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("수정")
                }
            }
            .disabled(isSaving)
        }
        .navigationTitle("복용 시간대 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { dismiss() }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        do {
            try await MedicationService.updateLog(id: entry.id, timing: selectedTiming)
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
