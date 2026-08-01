import SwiftUI

// 그날의 복용 체크(퀵버튼)만 처리한다 — 약 등록은 날짜와 무관한 전역 작업이라 설정 메뉴의
// MedicationManagementView로 옮겼다(mind-record 웹의 별도 "복용약 관리" 화면과 같은 구조).
struct MedicationEntryForm: View {
    let date: Date
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var selectedQuickTimings: Set<MedicationTiming> = []
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    @State private var entries: [MedicationLogEntry] = []
    @State private var isLoadingEntries = true
    @State private var entriesErrorMessage: String?

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
                .buttonStyle(CalendarSaveButtonStyle())
                .disabled(isSaving)
            }

            Section("이 날의 기록") {
                if isLoadingEntries {
                    ProgressView()
                } else if entries.isEmpty {
                    Text("이 날 복용 기록이 없어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.medication?.name ?? "약")
                            Spacer()
                            if let timing = entry.timing.flatMap(MedicationTiming.init(rawValue:)) {
                                Text(timing.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task { await removeEntries(at: offsets) }
                    }
                }
                if let entriesErrorMessage {
                    Text(entriesErrorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .task { await loadEntries() }
    }

    private func timingBinding(_ timing: MedicationTiming) -> Binding<Bool> {
        Binding(
            get: { selectedQuickTimings.contains(timing) },
            set: { isOn in
                if isOn { selectedQuickTimings.insert(timing) } else { selectedQuickTimings.remove(timing) }
            }
        )
    }

    private func loadEntries() async {
        isLoadingEntries = true
        do {
            entries = try await MedicationService.logs(on: date)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        isLoadingEntries = false
    }

    private func removeEntries(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await MedicationService.removeLog(id: entries[index].id)
            } catch {
                entriesErrorMessage = error.localizedDescription
            }
        }
        await loadEntries()
        await onRefresh()
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
                // 지난 날짜를 소급 입력하는 경우 오늘 알림과 무관하니, 오늘 날짜를 기록할 때만
                // 오늘 자 알림을 바로 취소한다.
                if Calendar.current.isDateInToday(date) {
                    ReminderNotificationService.shared.cancelTodayOccurrences(forTiming: timing)
                }
            }
            await onSaved()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
