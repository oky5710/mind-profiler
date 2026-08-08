import AuthenticationServices
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
    // 서버 JWT에 담긴 role 클레임을 그대로 읽기만 한다(서명 검증은 하지 않음) — 여기서는 화면에
    // 어떤 용어/메뉴를 보여줄지 정하는 데만 쓰고, 실제 접근 제어는 항상 백엔드가 담당한다.
    private(set) var role: UserRole?

    // 연구자는 원래 쓰던 rMSSD 용어를 그대로 알지만, 일반 사용자에게는 낯선 줄임말이라 보고서(의사
    // 대상)·설정 화면을 뺀 나머지 화면에서는 더 친숙한 "HRV"로 바꿔 보여준다. admin도 연구자와
    // 같은 기술 용어를 쓴다고 본다.
    var usesResearcherTerminology: Bool {
        role == .researcher || role == .admin
    }

    var hrvTerm: String {
        usesResearcherTerminology ? "rMSSD" : "HRV"
    }

    init() {
        let token = KeychainService.readToken(forKey: Self.tokenKey)
        isAuthenticated = token != nil
        role = token.flatMap(Self.decodeRole(fromToken:))
        shouldShowOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingPendingKey)

        // 저장된 JWT가 만료/폐기됐으면 어느 화면에서 API를 호출하든 401이 뜨는데, 그때까지는 앱이
        // 계속 "로그인된 상태"인 척 각 화면에 오류 메시지만 보여줬다 — 401을 로그아웃 신호로 받는다.
        APIClient.onUnauthorized = {
            Task { @MainActor [weak self] in
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
            let idToken = try await Self.googleIDToken(presenting: presentingViewController)

            let response: AuthTokenResponse = try await APIClient.shared.post(
                "/auth/google",
                body: GoogleLoginRequest(idToken: idToken),
                authorized: false
            )
            applySignIn(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // SignInWithAppleButton(AuthenticationServices)이 프레젠테이션까지 다 처리해서 넘겨주는
    // ASAuthorization을 그대로 받는다 — Google처럼 이 파일에서 컨트롤러/델리게이트를 직접 다룰
    // 필요가 없다.
    func signInWithApple(authorization: ASAuthorization) async {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else {
            errorMessage = "Apple 로그인에서 idToken을 받지 못했습니다."
            return
        }

        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        // Apple은 최초 인가 때만 이름을 내려준다 — 이후 로그인에서는 nil이라 서버가 이미 저장한
        // 이름을 그대로 유지한다.
        let fullName = credential.fullName.flatMap {
            PersonNameComponentsFormatter().string(from: $0)
        }.flatMap { $0.isEmpty ? nil : $0 }

        do {
            let response: AuthTokenResponse = try await APIClient.shared.post(
                "/auth/apple",
                body: AppleLoginRequest(idToken: idToken, fullName: fullName),
                authorized: false
            )
            applySignIn(response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applySignIn(_ response: AuthTokenResponse) {
        KeychainService.save(token: response.accessToken, forKey: Self.tokenKey)
        role = Self.decodeRole(fromToken: response.accessToken)
        // 이전에 로그인했던(다른) 계정이 온보딩을 마치지 않고 로그아웃했을 수 있어서, 기존
        // 사용자 로그인에서도 명시적으로 false를 써 그 상태가 이 계정까지 넘어오지 않게 한다.
        let isNewUser = response.isNewUser == true
        UserDefaults.standard.set(isNewUser, forKey: Self.onboardingPendingKey)
        shouldShowOnboarding = isNewUser
        isAuthenticated = true
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        KeychainService.deleteToken(forKey: Self.tokenKey)
        isAuthenticated = false
        role = nil
        shouldShowOnboarding = false
        UserDefaults.standard.set(false, forKey: Self.onboardingPendingKey)
        RecoveryScoreCache.clear()
    }

    // JWT의 서명은 검증하지 않는다 — 여기서는 화면에 보여줄 용어/메뉴를 정하는 용도일 뿐이고, 실제
    // 인가는 항상 백엔드가 Authorization 헤더의 토큰으로 매 요청마다 검증한다.
    private static func decodeRole(fromToken token: String) -> UserRole? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTRolePayload.self, from: data)
        else { return nil }
        return payload.role.flatMap(UserRole.init(rawValue:))
    }

    private struct JWTRolePayload: Decodable {
        let role: String?
    }

    func completeOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.onboardingPendingKey)
        shouldShowOnboarding = false
    }

    // GIDSignInResult는 Sendable이 아니므로 continuation을 통해 actor 경계를 넘기지 않는다.
    // SDK 콜백 안에서 필요한 문자열만 추출해 Sendable 값으로 반환한다.
    private static func googleIDToken(presenting viewController: UIViewController) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let idToken = result?.user.idToken?.tokenString {
                    continuation.resume(returning: idToken)
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
