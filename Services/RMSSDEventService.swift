import Foundation

enum RMSSDEventService {
    static func allEvents() async throws -> [RMSSDEventEntry] {
        try await APIClient.shared.get("/rmssd-events")
    }

    static func logEvent(_ request: RMSSDEventRequest) async throws {
        let _: RMSSDEventEntry = try await APIClient.shared.post("/rmssd-events", body: request)
    }

    static func removeEvent(id: String) async throws {
        let _: RMSSDEventEntry = try await APIClient.shared.delete("/rmssd-events/\(id)")
    }
}
