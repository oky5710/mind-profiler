import Foundation

enum MedicationService {
    // 캘린더 복용 체크는 mind-record 웹 MedicationForm.tsx와 동일하게 세 가지만 지원한다
    // (등록 자체는 5가지 시간대 전부 가능 — MedicationTiming.allCases).
    static let quickLogTimings: [MedicationTiming] = [.morning, .bedtime, .asNeeded]

    static func allMedications() async throws -> [MedicationEntry] {
        try await APIClient.shared.get("/medications")
    }

    static func addMedication(name: String, timings: [MedicationTiming]) async throws {
        let _: MedicationEntry = try await APIClient.shared.post(
            "/medications",
            body: MedicationRequest(name: name, timings: timings.map(\.rawValue))
        )
    }

    static func removeMedication(id: String) async throws {
        let _: MedicationEntry = try await APIClient.shared.delete("/medications/\(id)")
    }

    // 해당 시간대에 복용하는 것으로 등록된 약 전부를 한 번에 복용 처리 — 등록된 약이 없으면
    // 백엔드가 아무 로그도 만들지 않는다(약 없는데 눌러도 무해).
    static func logTiming(_ timing: MedicationTiming, date: Date) async throws {
        let _: [MedicationLogEntry] = try await APIClient.shared.post(
            "/medications/logs/quick",
            body: MedicationQuickLogRequest(timing: timing.rawValue, date: DateKey.string(from: date))
        )
    }
}
