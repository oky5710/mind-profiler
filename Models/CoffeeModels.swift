import Foundation

struct CoffeeLogRequest: Encodable {
    let date: String
    let type: String?
    let memo: String?
}

struct CoffeeLogEntry: Decodable {
    let id: String
    let date: String
    let type: String?
    let memo: String?
}
