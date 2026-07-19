import Foundation

struct ExerciseLogRequest: Encodable {
    let date: String
    let type: String
    let durationMinutes: Int
    let intensity: Int
}

struct ExerciseLogEntry: Decodable {
    let id: String
    let date: String
    let type: String
    let durationMinutes: Int
    // 단축어 자동화로 들어온 기록은 강도가 없을 수 있음(mind-record 웹과 동일).
    let intensity: Int?
}
