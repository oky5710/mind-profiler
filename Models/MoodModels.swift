import Foundation

struct MoodLogRequest: Encodable {
    let date: String
    let score: Int
}

struct MoodLogEntry: Decodable {
    let date: String
    let score: Int
}
