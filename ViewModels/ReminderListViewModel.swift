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

    // 같은 알림에 대한 토글 요청은 순서대로만 서버에 보낸다 — 스위치를 연달아 빠르게 누르면
    // 나중에 보낸 PATCH가 네트워크 사정으로 먼저 도착해 최신 선택을 덮어쓸 수 있어서, 이전 요청이
    // (성공이든 실패든) 완전히 끝난 뒤에야 다음 요청을 보낸다.
    private var pendingToggleTasks: [String: Task<Void, Never>] = [:]
    // 이 중 화면 갱신(load()/롤백/에러 표시)은 마지막으로 큐에 들어온 요청만 한다 — 안 그러면
    // 먼저 끝난 요청의 load()가 아직 대기 중인 더 최신 낙관적 표시를 순간적으로 덮어써서 스위치가
    // 깜빡였다가 되돌아오는 것처럼 보인다.
    private var latestToggleGeneration: [String: Int] = [:]

    // 삭제하지 않고 잠깐 켜고 끈다 — 요청 바디는 항상 전체 필드를 보내는 관례라, 기존 값 그대로에
    // isEnabled만 뒤집어서 다시 보낸다. 네트워크가 끝나기 전에 목록을 먼저 낙관적으로 바꿔서
    // 스위치가 바로 반응하게 한다(안 그러면 PATCH+재조회가 끝날 때까지 스위치가 안 움직이는 것처럼
    // 보인다).
    func setEnabled(_ isEnabled: Bool, for reminder: MedicationReminderEntry) async {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        let id = reminder.id
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

        let generation = (latestToggleGeneration[id] ?? 0) + 1
        latestToggleGeneration[id] = generation

        let priorTask = pendingToggleTasks[id]
        let task = Task { [weak self] in
            // 같은 알림에 대해 앞서 대기 중인 토글이 있으면, 그게 서버에 먼저 도착해 완전히
            // 끝날 때까지 기다린 뒤에야 이 요청을 보낸다.
            await priorTask?.value
            await self?.applyToggle(isEnabled: isEnabled, previous: previous, generation: generation)
        }
        pendingToggleTasks[id] = task
        await task.value
    }

    // load()가 시작하자마자 errorMessage를 지우므로, 실패 메시지는 load()가 끝난 뒤에 다시
    // 세팅해야 화면에 남는다.
    private func applyToggle(isEnabled: Bool, previous: MedicationReminderEntry, generation: Int) async {
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
        }

        // 이 사이 같은 알림에 대해 더 최신 토글이 큐에 들어왔으면, 화면 갱신은 그 최신 것에
        // 맡기고 여기서는 손대지 않는다(서버 PATCH는 순서대로 이미 반영됐다).
        guard latestToggleGeneration[previous.id] == generation else { return }

        if let updateError {
            // 되돌릴 위치를 지금 다시 찾는다 — await 하는 동안 목록이 재조회/삭제로 바뀌었을 수
            // 있어 처음 잡아둔 index가 더 이상 유효하지 않을 수 있다.
            if let currentIndex = reminders.firstIndex(where: { $0.id == previous.id }) {
                reminders[currentIndex] = previous
            }
        }

        // load()를 그대로 쓰지 않고 목록만 가볍게 다시 받아온다 — load()는 어차피 목록을 통째로
        // 덮어써서, 그 await가 끝나는 순간 다시 한번 generation을 확인해야 한다(fetch 도중에도
        // 더 최신 토글이 끼어들 수 있어서, guard를 fetch "전"에만 하면 fetch "중"에 끼어든 경우를
        // 놓친다).
        let refreshed = try? await MedicationReminderService.allReminders()
        if let refreshed, latestToggleGeneration[previous.id] == generation {
            reminders = refreshed
        }
        await ReminderNotificationService.shared.resync()
        if let updateError, latestToggleGeneration[previous.id] == generation {
            errorMessage = updateError
        }
    }
}
