import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Mind Profiler")
                .font(.largeTitle.bold())

            if authViewModel.isLoading {
                ProgressView()
            } else {
                Button {
                    Task { await authViewModel.signInWithGoogle() }
                } label: {
                    Label("Google로 로그인", systemImage: "person.crop.circle")
                        .font(Typography.button)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }

            if let errorMessage = authViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
