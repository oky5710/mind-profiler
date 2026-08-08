import Foundation

@MainActor
@Observable
final class UserManagementViewModel {
    private(set) var users: [AdminUserSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await APIClient.shared.get("/users")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // admin으로의 승격/강등은 이 화면에서 다루지 않는다(백엔드도 거부한다) — 호출부(Picker)가
    // 애초에 user/researcher만 선택지로 주지만, 방어적으로 한 번 더 막는다.
    func updateRole(for user: AdminUserSummary, to role: UserRole) async {
        guard role != .admin else { return }
        do {
            let updated: AdminUserSummary = try await APIClient.shared.patch(
                "/users/\(user.id)/role",
                body: UpdateUserRoleRequest(role: role.rawValue)
            )
            if let index = users.firstIndex(where: { $0.id == updated.id }) {
                users[index] = updated
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
