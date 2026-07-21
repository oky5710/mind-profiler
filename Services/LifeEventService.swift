import Foundation

enum LifeEventService {
    static func allEvents() async throws -> [LifeEventEntry] {
        try await APIClient.shared.get("/events")
    }

    static func entries(on date: Date) async throws -> [LifeEventEntry] {
        try await APIClient.shared.get("/events?date=\(DateKey.string(from: date))")
    }

    static func removeEvent(id: String) async throws {
        let _: LifeEventEntry = try await APIClient.shared.delete("/events/\(id)")
    }

    static func logEvent(dateTime: Date, type: LifeEventType, title: String, description: String?) async throws {
        let _: LifeEventEntry = try await APIClient.shared.post(
            "/events",
            body: LifeEventRequest(
                date: ISO8601DateFormatter().string(from: dateTime),
                type: type.rawValue,
                title: title,
                description: description
            )
        )
    }
}
