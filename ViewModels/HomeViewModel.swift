import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var photoURL: URL?
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private(set) var todayMoodScore: Int?
    private(set) var moodErrorMessage: String?
    private(set) var hasCheckedMood = false

    private(set) var todayCoffeeCount = 0
    private(set) var coffeeErrorMessage: String?

    private(set) var hasMorningMedicationTaken = false
    private(set) var hasBedtimeMedicationTaken = false
    private(set) var medicationErrorMessage: String?

    private var hasCheckedCoffee = false
    private var hasCheckedMedicationLogs = false

    func loadPhoto() async {
        isLoading = true
        errorMessage = nil
        photoURL = nil

        var attempts = 0
        var lastError: Error?
        while attempts <= 2 {
            do {
                photoURL = try await PixabayService.fetchRandomCatPhotoURL()
                isLoading = false
                return
            } catch {
                lastError = error
                attempts += 1

                if case APIError.server(let statusCode, _) = error, (400..<500).contains(statusCode) {
                    break
                }
                if attempts <= 2 {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        errorMessage = lastError?.localizedDescription
        isLoading = false
    }

    func loadTodayMoodIfNeeded() async {
        guard !hasCheckedMood else { return }
        hasCheckedMood = true

        do {
            todayMoodScore = try await MoodService.todayMood()?.score
        } catch {
            moodErrorMessage = error.localizedDescription
            // 실패하면 "확인함" 표시를 되돌려서, 다음에 홈 탭에 다시 들어왔을 때(onAppear) 재시도된다 —
            // 안 그러면 이 뷰모델이 살아있는 한(탭을 벗어났다 돌아와도) 영영 다시 시도하지 않는다.
            hasCheckedMood = false
        }
    }

    func logMood(score: Int) async {
        moodErrorMessage = nil
        do {
            try await MoodService.logTodayMood(score: score)
            todayMoodScore = score
        } catch {
            moodErrorMessage = error.localizedDescription
        }
    }

    func loadTodayCoffeeCountIfNeeded() async {
        guard !hasCheckedCoffee else { return }
        hasCheckedCoffee = true

        do {
            todayCoffeeCount = try await CoffeeService.todayCount()
        } catch {
            coffeeErrorMessage = error.localizedDescription
            hasCheckedCoffee = false
        }
    }

    func logCoffee() async {
        coffeeErrorMessage = nil
        do {
            try await CoffeeService.logQuickCoffee()
            todayCoffeeCount += 1
        } catch {
            coffeeErrorMessage = error.localizedDescription
        }
    }

    func loadTodayMedicationLogsIfNeeded() async {
        guard !hasCheckedMedicationLogs else { return }
        hasCheckedMedicationLogs = true
        if !(await refreshTodayMedicationLogs()) {
            hasCheckedMedicationLogs = false
        }
    }

    // mind-record 웹의 홈 화면 퀵버튼(EntryScreen.tsx)과 동일하게 아침/취침만 지원한다.
    func logMedicationQuick(_ timing: MedicationTiming) async {
        medicationErrorMessage = nil
        do {
            let result = try await MedicationService.logTiming(timing, date: Date())
            // 퀵로그는 그 시간대로 등록된 약 전부를 처리하는 거라, 등록된 약이 없으면 호출은
            // 성공해도 로그가 하나도 안 생긴다 — 체크마크가 안 뜨는 게 버그가 아니라 이 경우라는 걸
            // 안내한다(그 전까진 아무 피드백 없이 조용히 실패하는 것처럼 보였다).
            if result.isEmpty {
                medicationErrorMessage = "\(timing.label)에 복용하도록 등록된 약이 없어요. 캘린더에서 약을 등록해보세요."
            }
            await refreshTodayMedicationLogs()
        } catch {
            medicationErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func refreshTodayMedicationLogs() async -> Bool {
        do {
            let logs = try await MedicationService.logs(on: Date())
            hasMorningMedicationTaken = logs.contains { $0.timing == MedicationTiming.morning.rawValue && $0.taken }
            hasBedtimeMedicationTaken = logs.contains { $0.timing == MedicationTiming.bedtime.rawValue && $0.taken }
            return true
        } catch {
            medicationErrorMessage = error.localizedDescription
            return false
        }
    }
}
