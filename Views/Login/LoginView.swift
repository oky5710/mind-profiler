import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.colorScheme) private var colorScheme

    // 두 버튼이 같은 라운드 사각형 모양을 쓰도록, Apple 버튼의 코너 radius를 기준값으로 두고
    // Google 버튼도 buttonBorderShape로 맞춘다.
    private static let buttonCornerRadius: CGFloat = 8
    // SignInWithAppleButton은 UIKit 버튼(ASAuthorizationAppleIDButton)을 감싸고 있어 .frame(height:)를
    // 줘도 내부적으로 자기 높이를 그대로 쓸 수 있다 — 두 버튼을 같은 값으로 그냥 강제하는 대신,
    // Apple 버튼이 실제로 렌더링된 높이를 측정해서 Google 버튼에 그대로 적용한다.
    @State private var appleButtonHeight: CGFloat?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Mind Profiler")
                .font(.system(size: 28, weight: .semibold))

            VStack(spacing: 16) {
                if authViewModel.isLoading {
                    ProgressView()
                } else {
                    Button {
                        Task { await authViewModel.signInWithGoogle() }
                    } label: {
                        Label("Google로 로그인", systemImage: "person.crop.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: Self.buttonCornerRadius))
                    .frame(height: appleButtonHeight)
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
                    .cornerRadius(Self.buttonCornerRadius)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        appleButtonHeight = newHeight
                    }
                    .padding(.horizontal, 40)
                }

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(Typography.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.top, 16)

            Spacer()

            Text("건강 데이터는 사용자의 기기에서만 분석됩니다.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
