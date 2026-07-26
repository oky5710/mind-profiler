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
    // isEnabled만 뒤집어서 다시 보낸다. 네트워크가 끝나기 전에 목록을 먼저 낙관적으로 바꿔서
    // 스위치가 바로 반응하게 하고(안 그러면 PATCH+재조회가 끝날 때까지 스위치가 안 움직이는 것처럼
    // 보인다), 실패하면 원래 값으로 되돌린다. load()가 시작하자마자 errorMessage를 지우므로, 실패
    // 메시지는 load()가 끝난 뒤에 다시 세팅해야 화면에 남는다.
    func setEnabled(_ isEnabled: Bool, for reminder: MedicationReminderEntry) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let previous = reminders[index]
        reminders[index] = MedicationReminderEntry(
            id: previous.id,
            isEnabled: isEnabled,
            timing: previous.timing,
            repeatType: previous.repeatType,
            weekdays: previous.weekdays,
            time: previous.time,
            startDate: previous.startDate,
            endDate: previous.endDate
        )

        let request = MedicationReminderRequest(
            isEnabled: isEnabled,
            timing: previous.timing,
            repeatType: previous.repeatType,
            weekdays: previous.weekdays,
            time: previous.time,
            startDate: previous.startDate,
            endDate: previous.endDate
        )

        var updateError: String?
        do {
            try await MedicationReminderService.updateReminder(id: previous.id, request)
        } catch {
            updateError = error.localizedDescription
            reminders[index] = previous
        }
        await load()
        if let updateError {
            errorMessage = updateError
        }
    }
}
