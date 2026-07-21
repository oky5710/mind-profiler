import Foundation

struct MoodLogRequest: Encodable {
    let date: String
    let score: Int
}

struct MoodLogEntry: Decodable, Identifiable {
    let id: String
    let date: String
    let score: Int
}
