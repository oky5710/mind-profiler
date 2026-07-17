import Foundation

enum GoogleSignInConfig {
    static let iOSClientID = "30737503916-743t134hvofoe6e04ltg2v68f1fto487.apps.googleusercontent.com"

    // 백엔드가 idToken audience로 검증하는 값과 같아야 하므로 웹 클라이언트 ID를 그대로 사용.
    static let serverClientID = "30737503916-6edenfp163chg7kbjm6pqfrc5rsbmtmu.apps.googleusercontent.com"
}
