import SwiftUI

// 그날의 복용 체크(퀵버튼)만 처리한다 — 약 등록은 날짜와 무관한 전역 작업이라 설정 메뉴의
// MedicationManagementView로 옮겼다(mind-record 웹의 별도 "복용약 관리" 화면과 같은 구조).
struct MedicationEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var selectedQuickTimings: Set<MedicationTiming> = []
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        Form {
            Section("오늘 복용 처리") {
                ForEach(MedicationService.quickLogTimings) { timing in
                    Toggle(timing.label, isOn: timingBinding(timing))
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
    }

    private func timingBinding(_ timing: MedicationTiming) -> Binding<Bool> {
        Binding(
            get: { selectedQuickTimings.contains(timing) },
            set: { isOn in
                if isOn { selectedQuickTimings.insert(timing) } else { selectedQuickTimings.remove(timing) }
            }
        )
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
