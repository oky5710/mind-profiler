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
        await refreshTodayMedicationLogs()
    }

    // mind-record 웹의 홈 화면 퀵버튼(EntryScreen.tsx)과 동일하게 아침/취침만 지원한다.
    func logMedicationQuick(_ timing: MedicationTiming) async {
        medicationErrorMessage = nil
        do {
            try await MedicationService.logTiming(timing, date: Date())
            // 퀵로그는 그 시간대로 등록된 약 전부를 처리하는 거라, 등록된 약이 없으면 호출은
            // 성공해도 실제로 "복용됨" 상태가 안 될 수 있다 — 낙관적으로 갱신하지 않고 다시 조회해서
            // 진짜 상태를 반영한다.
            await refreshTodayMedicationLogs()
        } catch {
            medicationErrorMessage = error.localizedDescription
        }
    }

    private func refreshTodayMedicationLogs() async {
        do {
            let logs = try await MedicationService.logs(on: Date())
            hasMorningMedicationTaken = logs.contains { $0.timing == MedicationTiming.morning.rawValue && $0.taken }
            hasBedtimeMedicationTaken = logs.contains { $0.timing == MedicationTiming.bedtime.rawValue && $0.taken }
        } catch {
            medicationErrorMessage = error.localizedDescription
        }
    }
}
