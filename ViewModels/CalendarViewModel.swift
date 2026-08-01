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
    private var medicationLogsByDate: [String: [MedicationLogEntry]] = [:]
    private var eventsByDate: [String: [LifeEventEntry]] = [:]

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
            async let medicationLogs = MedicationService.allLogs()
            async let events = LifeEventService.allEvents()
            let (moodList, coffeeList, exerciseList, medicationLogList, eventList) = try await (moods, coffees, exercises, medicationLogs, events)

            // MoodLog.date는 시각 없는 순수 날짜(Prisma @db.Date)라, 일반 parseISODate로 인스턴트를
            // 만든 뒤 로컬 타임존으로 포맷하면 UTC보다 시간대가 뒤인 지역에서 하루 밀릴 수 있다 —
            // dateOnlyString으로 문자열의 날짜 부분만 그대로 키로 쓴다.
            var moodMap: [String: MoodLogEntry] = [:]
            for entry in moodList {
                guard let dayKey = DateKey.dateOnlyString(fromISO: entry.date) else { continue }
                moodMap[dayKey] = entry
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

            // MedicationLog.date도 MoodLog.date와 같은 순수 날짜 필드라 같은 이유로 dateOnlyString을
            // 쓴다 — parseISODate + 로컬 타임존이면 위와 같은 하루 밀림이 생길 수 있다.
            var medicationLogMap: [String: [MedicationLogEntry]] = [:]
            for entry in medicationLogList where entry.taken {
                guard let dayKey = DateKey.dateOnlyString(fromISO: entry.date) else { continue }
                medicationLogMap[dayKey, default: []].append(entry)
            }
            medicationLogsByDate = medicationLogMap

            // Event.date는 시각까지 있는 진짜 타임스탬프라(Prisma DateTime, @db.Date 아님) 커피/운동과
            // 같은 방식으로 parseISODate + 로컬 타임존 포맷을 그대로 쓴다.
            var eventMap: [String: [LifeEventEntry]] = [:]
            for entry in eventList {
                guard let date = DateKey.parseISODate(entry.date) else { continue }
                eventMap[DateKey.string(from: date), default: []].append(entry)
            }
            eventsByDate = eventMap
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

    func medicationLogs(on date: Date) -> [MedicationLogEntry] {
        medicationLogsByDate[DateKey.string(from: date)] ?? []
    }

    func events(on date: Date) -> [LifeEventEntry] {
        eventsByDate[DateKey.string(from: date)] ?? []
    }
}
