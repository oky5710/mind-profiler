import Foundation

@MainActor
@Observable
final class HRVAnalysisViewModel {
    struct ExamPoint: Identifiable {
        let date: Date
        let sdnn: Double
        var id: Date { date }
    }

    private(set) var examPoints: [ExamPoint] = []
    private(set) var moodSeries: [DailyValue] = []
    private(set) var coffeeSeries: [DailyValue] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var wearableHRVSeries: [DailyValue] = []
    private(set) var isHealthKitAuthorized = false
    private(set) var healthKitErrorMessage: String?

    private var hasLoaded = false
    private var hasCheckedHealthKit = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            async let exams = ExamService.allExams()
            async let moods = MoodService.allMoods()
            async let coffees = CoffeeService.allCoffees()
            let (examList, moodList, coffeeList) = try await (exams, moods, coffees)

            examPoints = examList
                .compactMap { entry -> ExamPoint? in
                    guard let date = DateKey.parseISODate(entry.examinedAt) else { return nil }
                    return ExamPoint(date: date, sdnn: entry.sdnn)
                }
                .sorted { $0.date < $1.date }

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

    func loadWearableHRVIfNeeded() async {
        guard !hasCheckedHealthKit else { return }
        hasCheckedHealthKit = true

        do {
            try await HealthKitService.requestAuthorization()
            let samples = try await HealthKitService.fetchHRVSamples()
            wearableHRVSeries = samples.map { DailyValue(date: $0.date, value: $0.value) }
            isHealthKitAuthorized = true
        } catch {
            healthKitErrorMessage = error.localizedDescription
        }
    }
}
