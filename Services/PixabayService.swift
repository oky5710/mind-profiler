import Foundation

enum PixabayService {
    // mind-record 웹의 NEXT_PUBLIC_PIXABAY_API_KEY와 동일한 키 (Pixabay 키는 클라이언트 노출 전제로 발급됨).
    private static let apiKey = "5516430-cfb5dd34c26991292858fee24"
    // per_page=200일 때 Pixabay는 (page-1)*per_page가 총 500건을 넘으면 400을 반환하므로 page는 1~3만 유효함.
    private static let maxPage = 3

    static func fetchRandomCatPhotoURL() async throws -> URL {
        var components = URLComponents(string: "https://pixabay.com/api/")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "q", value: "cat"),
            URLQueryItem(name: "image_type", value: "photo"),
            URLQueryItem(name: "per_page", value: "200"),
            URLQueryItem(name: "page", value: String(Int.random(in: 1...maxPage))),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.server(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        let decoded = try JSONDecoder().decode(PixabayResponse.self, from: data)
        guard !decoded.hits.isEmpty else {
            throw APIError.invalidResponse
        }

        let index = Int.random(in: 0..<decoded.hits.count)
        guard let url = URL(string: decoded.hits[index].webformatURL) else {
            throw APIError.invalidResponse
        }
        return url
    }
}
