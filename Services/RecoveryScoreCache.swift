import Foundation

// 앱을 다시 열었을 때(스플래시) 아직 HealthKit을 조회하기 전이라도 최근 회복 지수를 알 수 있도록
// 로컬(UserDefaults)에 캐시해 둔다 — CatPhotoService가 스플래시 고양이 사진 카테고리를 고를 때 참고한다.
// 오늘 날짜로 계산됐을 때만(HomeViewModel) 갱신하고, 과거 날짜를 조회할 때는 건드리지 않는다.
enum RecoveryScoreCache {
    private static let key = "recoveryScore.cachedValue"

    static var value: Int? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: key) != nil else { return nil }
            return defaults.integer(forKey: key)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
