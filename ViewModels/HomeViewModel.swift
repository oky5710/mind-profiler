import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var photoURL: URL?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    let message = ComfortMessages.all.randomElement()!

    private(set) var todayMoodScore: Int?
    private(set) var moodErrorMessage: String?
    private(set) var hasCheckedMood = false

    private(set) var todayCoffeeCount = 0
    private(set) var coffeeErrorMessage: String?

    private var hasCheckedCoffee = false

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
}
