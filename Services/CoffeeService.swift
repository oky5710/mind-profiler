import Foundation

enum CoffeeService {
    static let typeOptions = ["아메리카노", "라떼", "콜드브루", "디카페인", "에스프레소"]

    static func todayCount() async throws -> Int {
        let entries: [CoffeeLogEntry] = try await APIClient.shared.get("/coffee?date=\(DateKey.string(from: Date()))")
        return entries.count
    }

    static func allCoffees() async throws -> [CoffeeLogEntry] {
        try await APIClient.shared.get("/coffee")
    }

    static func logQuickCoffee() async throws {
        try await logCoffee(dateTime: Date(), type: "아메리카노", memo: nil)
    }

    static func logCoffee(dateTime: Date, type: String?, memo: String?) async throws {
        let _: CoffeeLogEntry = try await APIClient.shared.post(
            "/coffee",
            body: CoffeeLogRequest(date: ISO8601DateFormatter().string(from: dateTime), type: type, memo: memo)
        )
    }
}
