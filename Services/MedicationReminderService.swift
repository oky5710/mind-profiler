import Foundation

enum MedicationReminderService {
    static func allReminders() async throws -> [MedicationReminderEntry] {
        try await APIClient.shared.get("/medication-reminders")
    }

    static func addReminder(_ request: MedicationReminderRequest) async throws {
        let _: MedicationReminderEntry = try await APIClient.shared.post("/medication-reminders", body: request)
    }

    static func updateReminder(id: String, _ request: MedicationReminderRequest) async throws {
        let _: MedicationReminderEntry = try await APIClient.shared.patch("/medication-reminders/\(id)", body: request)
    }

    static func removeReminder(id: String) async throws {
        let _: MedicationReminderEntry = try await APIClient.shared.delete("/medication-reminders/\(id)")
    }
}
