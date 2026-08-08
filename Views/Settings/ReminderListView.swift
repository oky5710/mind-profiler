import SwiftUI

// 약 복용 리마인더 — 여기서 설정한 알림은 서버(MedicationReminder)에 저장되고, 실제 알림 예약은
// 기기에서 로컬로 한다(ReminderNotificationService). MedicationManagementView와 같은 구조(목록 +
// 추가 버튼 → 시트, 스와이프 삭제)에 수정 아이콘만 더했다.
struct ReminderListView: View {
    @State private var viewModel = ReminderListViewModel()
    @State private var isPresentingAddForm = false
    @State private var editingReminder: MedicationReminderEntry?
    // 약 복용 알림과 달리 서버에 저장할 게 없는 기기 로컬 켬/끔이라, 화면 상태를 따로 들고
    // 있다가 바꿀 때마다 NotificationPreferences(UserDefaults)에 반영한다.
    @State private var isRMSSDThresholdAlertEnabled = NotificationPreferences.isRMSSDThresholdAlertEnabled
    @State private var isSleepUpdateAlertEnabled = NotificationPreferences.isSleepUpdateAlertEnabled

    var body: some View {
        List {
            Section {
                Toggle("rMSSD 급격한 변화 알림", isOn: $isRMSSDThresholdAlertEnabled)
                    .onChange(of: isRMSSDThresholdAlertEnabled) { _, newValue in
                        NotificationPreferences.isRMSSDThresholdAlertEnabled = newValue
                    }
                Toggle("수면 데이터 업데이트 알림", isOn: $isSleepUpdateAlertEnabled)
                    .onChange(of: isSleepUpdateAlertEnabled) { _, newValue in
                        NotificationPreferences.isSleepUpdateAlertEnabled = newValue
                    }
            } footer: {
                Text("rMSSD가 평소보다 급격히 낮거나 높아졌을 때, 그리고 새 수면 데이터가 동기화됐을 때 알려줘요.")
            }

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
                            // 꺼진 알림은 옅게 표시해서 "꺼져 있음" 상태를 바로 알 수 있게 한다
                            // (ui-style.md 범례 항목 숨김 표시와 같은 원칙).
                            .opacity(reminder.isEnabled ? 1 : 0.4)
                            Spacer()
                            Toggle("", isOn: enabledBinding(for: reminder))
                                .labelsHidden()
                            Button {
                                editingReminder = reminder
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        Task { await viewModel.remove(at: offsets) }
                    }
                }
            }

            Section("알림 예약 상태") {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("앞으로 예약된 알림 \(viewModel.scheduledNotificationCount)개")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            if viewModel.availableTimings.isEmpty && !viewModel.isLoading {
                Section {
                    Text("먼저 설정의 \"약 등록\"에서 약을 등록해야 알림을 만들 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("알림 설정")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isPresentingAddForm = true
            } label: {
                Label("알림 추가", systemImage: "bell.badge")
                    .font(Typography.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || viewModel.availableTimings.isEmpty)
            .opacity(viewModel.isLoading || viewModel.availableTimings.isEmpty ? 0.5 : 1)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
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

    private func enabledBinding(for reminder: MedicationReminderEntry) -> Binding<Bool> {
        Binding(
            get: { reminder.isEnabled },
            set: { newValue in
                Task { await viewModel.setEnabled(newValue, for: reminder) }
            }
        )
    }

    private func summary(for reminder: MedicationReminderEntry) -> String {
        let repeatText: String
        if reminder.repeatType == ReminderRepeatType.weekly.rawValue {
            let days = reminder.weekdays.sorted().map { ReminderWeekday.shortLabel(for: $0) }.joined(separator: "·")
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
