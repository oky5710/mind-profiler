import Foundation

struct ExerciseLogRequest: Encodable {
    let type: String
    let startedAt: String
    let endedAt: String
    let intensity: Int
}

struct ExerciseLogEntry: Decodable, Identifiable {
    let id: String
    let type: String
    let startedAt: String
    let endedAt: String
    // 단축어 자동화로 들어온 기록은 강도가 없을 수 있음(mind-record 웹과 동일).
    let intensity: Int?
}
