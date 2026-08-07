import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.colorScheme) private var colorScheme

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

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        Task { await authViewModel.signInWithApple(authorization: authorization) }
                    case .failure(let error):
                        authViewModel.errorMessage = error.localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 44)
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
