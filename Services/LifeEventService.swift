import Foundation

enum LifeEventService {
    static func allEvents() async throws -> [LifeEventEntry] {
        try await APIClient.shared.get("/events")
    }

    static func entries(on date: Date) async throws -> [LifeEventEntry] {
        try await APIClient.shared.get("/events?date=\(DateKey.string(from: date))")
    }

    static func symptomEntries(on date: Date) async throws -> [LifeEventEntry] {
        try await entries(on: date).filter { $0.symptomType != nil }
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

    static func logSymptom(
        dateTime: Date,
        symptom: SymptomType,
        intensity: Int,
        description: String?
    ) async throws {
        let _: LifeEventEntry = try await APIClient.shared.post(
            "/events",
            body: SymptomRequest(
                date: ISO8601DateFormatter().string(from: dateTime),
                title: symptom.label,
                description: description,
                intensity: intensity
            )
        )
    }
}
