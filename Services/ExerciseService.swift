import Foundation

enum ExerciseService {
    // mind-record 웹 ExerciseForm.tsx와 동일한 종류/강도 옵션.
    static let typeOptions = ["유산소", "근력 운동"]
    static let intensityLabels = ["", "매우 쉬움", "쉬움", "보통", "힘듦", "매우 힘듦"]

    static func allExercises() async throws -> [ExerciseLogEntry] {
        try await APIClient.shared.get("/exercises")
    }

    static func logExercise(date: Date, type: String, durationMinutes: Int, intensity: Int) async throws {
        let _: ExerciseLogEntry = try await APIClient.shared.post(
            "/exercises",
            body: ExerciseLogRequest(
                date: DateKey.string(from: date),
                type: type,
                durationMinutes: durationMinutes,
                intensity: intensity
            )
        )
    }
}
