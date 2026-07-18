import Foundation

enum APIError: Error {
    case invalidResponse
    case server(statusCode: Int, message: String?)
    case decoding(Error)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "서버 응답이 올바르지 않습니다."
        case .server(let statusCode, let message):
            "서버 오류 (\(statusCode))" + (message.map { ": \($0)" } ?? "")
        case .decoding(let error):
            "응답을 해석하지 못했습니다: \(error.localizedDescription)"
        }
    }
}

private nonisolated struct EmptyBody: Encodable {}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://mind-profiler-backend.onrender.com")!
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {}

    func get<Response: Decodable>(_ path: String, authorized: Bool = true) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<EmptyBody>.none, authorized: authorized)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> Response {
        try await send(path: path, method: "POST", body: body, authorized: authorized)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        authorized: Bool
    ) async throws -> Response {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authorized, let token = KeychainService.readToken(forKey: "accessToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
