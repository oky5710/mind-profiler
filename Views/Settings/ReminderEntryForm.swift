import SwiftUI

struct ReminderEntryForm: View {
    let availableTimings: [MedicationTiming]
    // 이 값이 있으면 새로 만들지 않고 이 알림을 수정한다.
    var editingEntry: MedicationReminderEntry? = nil
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    // 켜고 끄는 스위치는 목록 화면 행에서 바로 조작한다 — 이 폼에서는 수정 시 기존 값을 그대로
    // 들고 있다가 저장할 때 같이 보낸다(요청 바디는 항상 전체 필드를 보내는 관례).
    @State private var isEnabled = true
    @State private var selectedTiming: MedicationTiming
    @State private var repeatType: ReminderRepeatType = .daily
    @State private var selectedWeekdays: Set<Int> = []
    @State private var time: Date
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.startOfDay(for: Date())
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(availableTimings: [MedicationTiming], editingEntry: MedicationReminderEntry? = nil, onSaved: @escaping () async -> Void) {
        self.availableTimings = availableTimings
        self.editingEntry = editingEntry
        self.onSaved = onSaved
        self._selectedTiming = State(initialValue: availableTimings.first ?? .morning)
        self._time = State(initialValue: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("내용") {
                    Picker("내용", selection: $selectedTiming) {
                        ForEach(availableTimings) { timing in
                            Text(timing.label).tag(timing)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("반복 일정") {
                    Picker("반복 일정", selection: $repeatType) {
                        ForEach(ReminderRepeatType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if repeatType == .weekly {
                        ForEach(ReminderWeekday.all, id: \.self) { weekday in
                            Toggle(ReminderWeekday.shortLabel(for: weekday), isOn: weekdayBinding(weekday))
                        }
                    }
                }

                Section("시간") {
                    DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
                }

                Section("기간") {
                    DatePicker("시작일", selection: $startDate, displayedComponents: .date)
                    Toggle("무기한", isOn: Binding(get: { !hasEndDate }, set: { hasEndDate = !$0 }))
                    if hasEndDate {
                        DatePicker("종료일", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text(editingEntry == nil ? "저장" : "수정")
                    }
                }
                .disabled(isSaving)
            }
            .navigationTitle(editingEntry == nil ? "알림 추가" : "알림 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task {
                if let editingEntry {
                    prefill(from: editingEntry)
                }
            }
        }
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { selectedWeekdays.contains(weekday) },
            set: { isOn in
                if isOn { selectedWeekdays.insert(weekday) } else { selectedWeekdays.remove(weekday) }
            }
        )
    }

    private func prefill(from entry: MedicationReminderEntry) {
        isEnabled = entry.isEnabled
        if let timing = MedicationTiming(rawValue: entry.timing) {
            selectedTiming = timing
        }
        if let type = ReminderRepeatType(rawValue: entry.repeatType) {
            repeatType = type
        }
        selectedWeekdays = Set(entry.weekdays)
        if let parsedTime = Self.timeFormatter.date(from: entry.time) {
            time = parsedTime
        }
        if let parsedStart = DateKey.parseISODate(entry.startDate) {
            startDate = Calendar.current.startOfDay(for: parsedStart)
        }
        if let endDateString = entry.endDate, let parsedEnd = DateKey.parseISODate(endDateString) {
            hasEndDate = true
            endDate = Calendar.current.startOfDay(for: parsedEnd)
        } else {
            hasEndDate = false
        }
    }

    private func save() async {
        errorMessage = nil
        if repeatType == .weekly && selectedWeekdays.isEmpty {
            errorMessage = "요일을 하나 이상 선택해주세요."
            return
        }

        isSaving = true
        let request = MedicationReminderRequest(
            isEnabled: isEnabled,
            timing: selectedTiming.rawValue,
            repeatType: repeatType.rawValue,
            weekdays: repeatType == .weekly ? Array(selectedWeekdays).sorted() : [],
            time: Self.timeFormatter.string(from: time),
            startDate: DateKey.string(from: startDate),
            endDate: hasEndDate ? DateKey.string(from: endDate) : nil
        )

        do {
            if let editingEntry {
                try await MedicationReminderService.updateReminder(id: editingEntry.id, request)
            } else {
                try await MedicationReminderService.addReminder(request)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
