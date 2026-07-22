import Foundation

@MainActor
@Observable
final class CalendarViewModel {
    private(set) var year: Int
    private(set) var month: Int // 1...12
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var moodsByDate: [String: MoodLogEntry] = [:]
    private var coffeesByDate: [String: [CoffeeLogEntry]] = [:]
    private var exercisesByDate: [String: [ExerciseLogEntry]] = [:]

    init(referenceDate: Date = Date()) {
        let components = Calendar.current.dateComponents([.year, .month], from: referenceDate)
        year = components.year ?? 2026
        month = components.month ?? 1
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            async let moods = MoodService.allMoods()
            async let coffees = CoffeeService.allCoffees()
            async let exercises = ExerciseService.allExercises()
            let (moodList, coffeeList, exerciseList) = try await (moods, coffees, exercises)

            var moodMap: [String: MoodLogEntry] = [:]
            for entry in moodList {
                guard let date = DateKey.parseISODate(entry.date) else { continue }
                moodMap[DateKey.string(from: date)] = entry
            }
            moodsByDate = moodMap

            var coffeeMap: [String: [CoffeeLogEntry]] = [:]
            for entry in coffeeList {
                guard let date = DateKey.parseISODate(entry.date) else { continue }
                coffeeMap[DateKey.string(from: date), default: []].append(entry)
            }
            coffeesByDate = coffeeMap

            var exerciseMap: [String: [ExerciseLogEntry]] = [:]
            for entry in exerciseList {
                guard let start = DateKey.parseISODate(entry.startedAt) else { continue }
                exerciseMap[DateKey.string(from: start), default: []].append(entry)
            }
            exercisesByDate = exerciseMap
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func goToPreviousMonth() {
        if month == 1 {
            month = 12
            year -= 1
        } else {
            month -= 1
        }
    }

    func goToNextMonth() {
        if month == 12 {
            month = 1
            year += 1
        } else {
            month += 1
        }
    }

    var weeks: [[Date?]] {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return []
        }
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth) // 1 = Sunday
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: weekdayOfFirst - 1)
        for day in 1...daysInMonth {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    func mood(on date: Date) -> MoodLogEntry? {
        moodsByDate[DateKey.string(from: date)]
    }

    func coffees(on date: Date) -> [CoffeeLogEntry] {
        coffeesByDate[DateKey.string(from: date)] ?? []
    }

    func exercises(on date: Date) -> [ExerciseLogEntry] {
        exercisesByDate[DateKey.string(from: date)] ?? []
    }
}
