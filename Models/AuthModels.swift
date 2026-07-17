import Foundation

struct GoogleLoginRequest: Encodable {
    let idToken: String
}

struct AuthTokenResponse: Decodable {
    let accessToken: String
}
