import SwiftUI

// 타이포그래피의 단일 소스. 화면에서는 `.font(.system(size: 17))`처럼 크기를 직접 지정하지 않고
// 반드시 이 토큰들을 사용한다 (docs/design-system.md의 Typography 섹션 참고).
enum Typography {
    static let largeTitle = Font.system(size: 28, weight: .bold)
    static let screenTitle = Font.system(size: 18, weight: .bold)
    static let sectionTitle = Font.system(size: 20, weight: .bold)
    static let reportSectionTitle = Font.system(size: 19, weight: .bold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 17, weight: .regular)
    static let button = Font.system(size: 18, weight: .semibold)
    static let secondary = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)
    static let caption2 = Font.system(size: 11, weight: .regular)
    static let sleepStageLabel = Font.system(size: 12, weight: .regular)
    static let sleepDate = Font.system(size: 17, weight: .semibold)
    static let bigStatValue = Font.system(size: 24, weight: .bold)
    static let splashTagline = Font.system(size: 28, weight: .bold)
    static let chartAxisLabel = Font.system(size: 9, weight: .regular)
}
