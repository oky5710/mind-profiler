import SwiftUI

// 캘린더 날짜 요약 시트의 연필 아이콘으로 들어오는 수정 화면 — 복용 기록 자체(누가/언제 눌렀는지)는
// 바꿀 게 없고, 잘못 고른 시간대(아침/점심/저녁/취침전/필요시)만 바로잡는 용도라 다른 입력 폼처럼
// 크지 않다. 화면은 시간대 하나를 "그 시간대를 챙겼는지"로 다루므로, 그 시간대에 걸린 약 로그가
// 여러 개(예: 아침약 10개)여도 한 번에 전부 새 시간대로 옮긴다 — 그중 하나만 골라 옮기는 개념이
// 아니다.
struct MedicationLogEditForm: View {
    let entries: [MedicationLogEntry]
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTiming: MedicationTiming
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entries: [MedicationLogEntry], onSaved: @escaping () async -> Void) {
        self.entries = entries
        self.onSaved = onSaved
        self._selectedTiming = State(initialValue: entries.first?.timing.flatMap(MedicationTiming.init(rawValue:)) ?? .morning)
    }

    var body: some View {
        Form {
            Section {
                Picker("시간대", selection: $selectedTiming) {
                    ForEach(MedicationTiming.allCases) { timing in
                        Text(timing.label).tag(timing)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                if entries.count > 1 {
                    Text("이 시간대에 걸린 약 \(entries.count)개가 한 번에 새 시간대로 옮겨져요.")
                }
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
            for entry in entries {
                try await MedicationService.updateLog(id: entry.id, timing: selectedTiming)
            }
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
