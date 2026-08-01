import Foundation
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class AuthViewModel {
    private static let tokenKey = "accessToken"
    private static let onboardingPendingKey = "auth.onboardingPending"

    var isAuthenticated: Bool
    var shouldShowOnboarding: Bool
    var isLoading = false
    var errorMessage: String?

    init() {
        isAuthenticated = KeychainService.readToken(forKey: Self.tokenKey) != nil
        shouldShowOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingPendingKey)

        // 저장된 JWT가 만료/폐기됐으면 어느 화면에서 API를 호출하든 401이 뜨는데, 그때까지는 앱이
        // 계속 "로그인된 상태"인 척 각 화면에 오류 메시지만 보여줬다 — 401을 로그아웃 신호로 받는다.
        APIClient.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.signOut()
            }
        }
    }

    func signInWithGoogle() async {
        guard let presentingViewController = Self.topViewController() else {
            errorMessage = "로그인 화면을 표시할 창을 찾지 못했습니다."
            return
        }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Self.signIn(presenting: presentingViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google 로그인에서 idToken을 받지 못했습니다."
                return
            }

            let response: AuthTokenResponse = try await APIClient.shared.post(
                "/auth/google",
                body: GoogleLoginRequest(idToken: idToken),
                authorized: false
            )

            KeychainService.save(token: response.accessToken, forKey: Self.tokenKey)
            if response.isNewUser == true {
                UserDefaults.standard.set(true, forKey: Self.onboardingPendingKey)
                shouldShowOnboarding = true
            }
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        KeychainService.deleteToken(forKey: Self.tokenKey)
        isAuthenticated = false
    }

    func completeOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.onboardingPendingKey)
        shouldShowOnboarding = false
    }

    private static func signIn(presenting viewController: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: APIError.invalidResponse)
                }
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
