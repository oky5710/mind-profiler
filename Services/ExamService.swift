import Foundation

enum ExamService {
    static func allExams() async throws -> [ExamEntry] {
        try await APIClient.shared.get("/hrv")
    }

    static func createExam(_ request: ExamRequest) async throws {
        let _: ExamEntry = try await APIClient.shared.post("/hrv", body: request)
    }
}
