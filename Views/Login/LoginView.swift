import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.colorScheme) private var colorScheme

    // 두 버튼이 같은 라운드 사각형 모양을 쓰도록, Apple 버튼의 코너 radius를 기준값으로 두고
    // Google 버튼도 buttonBorderShape로 맞춘다.
    private static let buttonCornerRadius: CGFloat = 8
    // ASAuthorizationAppleIDButton은 자체 높이 제약(<= 64)을 갖고 있어서, 명시적인 높이를 안 주면
    // 부모(Spacer가 있는 VStack)가 제안하는 임의의 큰 높이와 그 내부 제약이 충돌해 오토레이아웃
    // 경고를 낸다 — 반드시 그 범위(30~64) 안의 고정 높이를 줘야 한다. 두 버튼 다 같은 값을 써서
    // 굳이 서로의 실제 렌더링 높이를 측정할 필요도 없다.
    private static let appleButtonHeight: CGFloat = 44
    private static let googleButtonHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("LoginLogo")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(146.0 / 111.0, contentMode: .fit)
                .foregroundStyle(.primary)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.6 }

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
                            // borderedProminent의 배경은 라벨 크기에 맞춰 그려져서, 바깥쪽에만
                            // frame(height:)를 주면 그 배경은 그대로고 남는 공간만 빈 채로 커진다 —
                            // 라벨 자체를 이 높이로 채워야 보라색 배경도 같이 늘어난다.
                            .frame(height: Self.googleButtonHeight)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: Self.buttonCornerRadius))
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
                    .frame(height: Self.appleButtonHeight)
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
