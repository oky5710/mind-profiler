import Foundation

enum MoodService {
    static let options: [(score: Int, emoji: String)] = [
        (1, "😞"),
        (2, "😕"),
        (3, "😐"),
        (4, "🙂"),
        (5, "😄"),
    ]

    static func todayMood() async throws -> MoodLogEntry? {
        let entries: [MoodLogEntry] = try await APIClient.shared.get("/moods?date=\(DateKey.string(from: Date()))")
        return entries.first
    }

    static func allMoods() async throws -> [MoodLogEntry] {
        try await APIClient.shared.get("/moods")
    }

    static func entries(on date: Date) async throws -> [MoodLogEntry] {
        try await APIClient.shared.get("/moods?date=\(DateKey.string(from: date))")
    }

    static func removeMood(id: String) async throws {
        let _: MoodLogEntry = try await APIClient.shared.delete("/moods/\(id)")
    }

    static func logMood(date: String, score: Int) async throws {
        let _: MoodLogEntry = try await APIClient.shared.post(
            "/moods",
            body: MoodLogRequest(date: date, score: score)
        )
    }

    static func logTodayMood(score: Int) async throws {
        try await logMood(date: DateKey.string(from: Date()), score: score)
    }
}
