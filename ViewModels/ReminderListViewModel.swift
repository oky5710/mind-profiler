import Foundation

@MainActor
@Observable
final class ReminderListViewModel {
    private(set) var reminders: [MedicationReminderEntry] = []
    private(set) var isLoading = true
    var errorMessage: String?

    // "내용" 선택지 — 실제로 등록해 둔 약들의 복용 시간대 합집합에서 고른다(등록된 약이 아침
    // 시간대만 있으면 아침만 선택 가능). MedicationTiming.allCases 순서(아침→점심→저녁→취침전→
    // 필요시)를 그대로 유지한다.
    private(set) var availableTimings: [MedicationTiming] = []

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await ReminderNotificationService.shared.requestAuthorization()

            async let remindersTask = MedicationReminderService.allReminders()
            async let medicationsTask = MedicationService.allMedications()
            let (loadedReminders, medications) = try await (remindersTask, medicationsTask)

            reminders = loadedReminders
            let registeredTimings = Set(medications.flatMap(\.timings))
            availableTimings = MedicationTiming.allCases.filter { registeredTimings.contains($0.rawValue) }

            await ReminderNotificationService.shared.resync()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func remove(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await MedicationReminderService.removeReminder(id: reminders[index].id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await load()
    }

    // 삭제하지 않고 잠깐 켜고 끈다 — 요청 바디는 항상 전체 필드를 보내는 관례라, 기존 값 그대로에
    // isEnabled만 뒤집어서 다시 보낸다.
    func setEnabled(_ isEnabled: Bool, for reminder: MedicationReminderEntry) async {
        let request = MedicationReminderRequest(
            isEnabled: isEnabled,
            timing: reminder.timing,
            repeatType: reminder.repeatType,
            weekdays: reminder.weekdays,
            time: reminder.time,
            startDate: reminder.startDate,
            endDate: reminder.endDate
        )
        do {
            try await MedicationReminderService.updateReminder(id: reminder.id, request)
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
    }
}
