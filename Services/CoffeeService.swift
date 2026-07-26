import Foundation

enum CoffeeService {
    // mind-record 웹 CoffeeForm.tsx의 COFFEE_TYPES와 동일한 목록/순서("직접입력" 제외 — iOS는
    // 별도 토글로 처리).
    static let typeOptions = ["아메리카노", "라떼", "카푸치노", "에스프레소", "콜드브루"]

    static func todayCount() async throws -> Int {
        let entries: [CoffeeLogEntry] = try await APIClient.shared.get("/coffee?date=\(DateKey.string(from: Date()))")
        return entries.count
    }

    static func allCoffees() async throws -> [CoffeeLogEntry] {
        try await APIClient.shared.get("/coffee")
    }

    static func entries(on date: Date) async throws -> [CoffeeLogEntry] {
        try await APIClient.shared.get("/coffee?date=\(DateKey.string(from: date))")
    }

    static func removeCoffee(id: String) async throws {
        let _: CoffeeLogEntry = try await APIClient.shared.delete("/coffee/\(id)")
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

    static func updateCoffee(id: String, dateTime: Date, type: String?, memo: String?) async throws {
        let _: CoffeeLogEntry = try await APIClient.shared.patch(
            "/coffee/\(id)",
            body: CoffeeLogRequest(date: ISO8601DateFormatter().string(from: dateTime), type: type, memo: memo)
        )
    }
}
