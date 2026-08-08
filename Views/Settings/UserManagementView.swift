import SwiftUI

struct UserManagementView: View {
    @State private var viewModel = UserManagementViewModel()

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(.red)
            }

            ForEach(viewModel.users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.name)
                        .font(Typography.cardTitle)
                    Text(user.email)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)

                    // admin으로의 승격/강등은 DB에서만 한다 — 이 화면에서는 admin 행에 선택지를
                    // 아예 주지 않는다(백엔드도 이 API로는 거부한다).
                    if user.role == .admin {
                        Text("관리자")
                            .font(Typography.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("권한", selection: Binding(
                            get: { user.role },
                            set: { newRole in Task { await viewModel.updateRole(for: user, to: newRole) } }
                        )) {
                            Text("사용자").tag(UserRole.user)
                            Text("연구자").tag(UserRole.researcher)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.users.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("사용자 권한 관리")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }
}
