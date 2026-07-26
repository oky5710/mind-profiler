import SwiftUI

// 약 복용 리마인더 — 여기서 설정한 알림은 서버(MedicationReminder)에 저장되고, 실제 알림 예약은
// 기기에서 로컬로 한다(ReminderNotificationService). MedicationManagementView와 같은 구조(목록 +
// 추가 버튼 → 시트, 스와이프 삭제)에 수정 아이콘만 더했다.
struct ReminderListView: View {
    @State private var viewModel = ReminderListViewModel()
    @State private var isPresentingAddForm = false
    @State private var editingReminder: MedicationReminderEntry?

    var body: some View {
        List {
            Section("등록된 알림") {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.reminders.isEmpty {
                    Text("등록된 알림이 없어요. 아래에서 추가해보세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.reminders) { reminder in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MedicationTiming(rawValue: reminder.timing)?.label ?? reminder.timing)
                                Text(summary(for: reminder))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 16) {
                                Button {
                                    editingReminder = reminder
                                } label: {
                                    Image(systemName: "pencil")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        Task { await viewModel.remove(at: offsets) }
                    }
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                if viewModel.availableTimings.isEmpty && !viewModel.isLoading {
                    Text("먼저 설정의 \"약 등록\"에서 약을 등록해야 알림을 만들 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        isPresentingAddForm = true
                    } label: {
                        Label("알림 추가", systemImage: "bell.badge")
                    }
                    .disabled(viewModel.availableTimings.isEmpty)
                }
            }
        }
        .navigationTitle("알림 설정")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $isPresentingAddForm) {
            ReminderEntryForm(availableTimings: viewModel.availableTimings) {
                await viewModel.load()
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEntryForm(availableTimings: viewModel.availableTimings, editingEntry: reminder) {
                await viewModel.load()
            }
        }
    }

    private func summary(for reminder: MedicationReminderEntry) -> String {
        let repeatText: String
        if reminder.repeatType == ReminderRepeatType.weekly.rawValue {
            let days = reminder.weekdays.sorted().map(ReminderWeekday.shortLabel(for:)).joined(separator: "·")
            repeatText = days.isEmpty ? "매주" : "매주 \(days)"
        } else {
            repeatText = "매일"
        }
        return "\(repeatText) · \(reminder.time)"
    }
}

#Preview {
    NavigationStack {
        ReminderListView()
    }
}
