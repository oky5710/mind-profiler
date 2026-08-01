import Foundation

struct GoogleLoginRequest: Encodable {
    let idToken: String
}

struct AuthTokenResponse: Decodable {
    let accessToken: String
    // 백엔드 배포 순서가 달라도 기존 응답을 받을 수 있게 optional로 둔다.
    let isNewUser: Bool?
}
