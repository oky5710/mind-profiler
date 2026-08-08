import Foundation

// admin이 설정 > 사용자 권한 관리 화면에서 다루는 목록 항목. PATCH 응답도 같은 모양이라
// 갱신 후 그대로 교체해 넣을 수 있다.
struct AdminUserSummary: Decodable, Identifiable {
    let id: String
    let email: String
    let name: String
    let role: UserRole
}

// 백엔드가 admin으로의 승격/강등은 이 API로 받지 않아서(docs/architecture.md 참고),
// UserRole 전체가 아니라 user/researcher만 값으로 보낸다.
struct UpdateUserRoleRequest: Encodable {
    let role: String
}
