import Foundation
import GoogleSignIn
import UIKit

@MainActor
@Observable
final class AuthViewModel {
    private static let tokenKey = "accessToken"

    var isAuthenticated: Bool
    var isLoading = false
    var errorMessage: String?

    init() {
        isAuthenticated = KeychainService.readToken(forKey: Self.tokenKey) != nil
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
