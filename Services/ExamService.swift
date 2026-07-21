import Foundation

enum ExamService {
    static func allExams() async throws -> [ExamEntry] {
        try await APIClient.shared.get("/hrv")
    }

    // 백엔드 GET /hrv는 날짜 필터를 지원하지 않아 전체를 받아 클라이언트에서 그 날짜만 걸러낸다.
    static func entries(on date: Date) async throws -> [ExamEntry] {
        let dayKey = DateKey.string(from: date)
        return try await allExams().filter { entry in
            guard let examinedAt = DateKey.parseISODate(entry.examinedAt) else { return false }
            return DateKey.string(from: examinedAt) == dayKey
        }
    }

    static func createExam(_ request: ExamRequest) async throws {
        let _: ExamEntry = try await APIClient.shared.post("/hrv", body: request)
    }

    static func removeExam(id: Int) async throws {
        let _: ExamEntry = try await APIClient.shared.delete("/hrv/\(id)")
    }
}
