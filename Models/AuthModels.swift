import Foundation

struct GoogleLoginRequest: Encodable {
    let idToken: String
}

struct AppleLoginRequest: Encodable {
    let idToken: String
    let fullName: String?
}

struct AuthTokenResponse: Decodable {
    let accessToken: String
    // 백엔드 배포 순서가 달라도 기존 응답을 받을 수 있게 optional로 둔다.
    let isNewUser: Bool?
}

// 클라이언트가 지정/변경할 수 없고 DB에서만 승격된다(docs/architecture.md 참고) — JWT에 담긴 값을
// 읽기만 한다. 알 수 없는 문자열(백엔드에 새 역할이 추가된 경우 등)은 디코딩에서 nil로 빠지고,
// 화면들은 nil을 항상 "user"와 동일하게(가장 제한적으로) 다룬다.
enum UserRole: String, Decodable {
    case user
    case researcher
    case admin
}
