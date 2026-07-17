import Foundation

@MainActor
@Observable
final class StatisticsViewModel {
    struct DailyValue: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private(set) var moodSeries: [DailyValue] = []
    private(set) var coffeeSeries: [DailyValue] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            async let moods = MoodService.allMoods()
            async let coffees = CoffeeService.allCoffees()
            let (moodList, coffeeList) = try await (moods, coffees)

            moodSeries = moodList
                .compactMap { entry -> DailyValue? in
                    guard let date = DateKey.parseISODate(entry.date) else { return nil }
                    return DailyValue(date: Calendar.current.startOfDay(for: date), value: Double(entry.score))
                }
                .sorted { $0.date < $1.date }

            var coffeeCounts: [Date: Int] = [:]
            for entry in coffeeList {
                guard let date = DateKey.parseISODate(entry.date) else { continue }
                coffeeCounts[Calendar.current.startOfDay(for: date), default: 0] += 1
            }
            coffeeSeries = coffeeCounts
                .map { DailyValue(date: $0.key, value: Double($0.value)) }
                .sorted { $0.date < $1.date }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
