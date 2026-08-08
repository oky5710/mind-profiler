import SwiftUI
import UIKit

// 타이포그래피의 단일 소스. 화면에서 `.font(.system(size: 17))`처럼 크기를 직접 지정하지 않고
// 반드시 이 토큰들을 사용한다 (docs/design-system.md의 Typography 섹션 참고).
//
// 아래 pt 값은 사용자가 손쉬운 사용의 텍스트 크기를 표준(기본값)으로 뒀을 때의 기준 크기다 — 실제
// 렌더링 크기는 각 토큰에 지정된 텍스트 스타일(relativeTo)을 따라 Dynamic Type 설정에 맞춰
// 커진다/작아진다. `Font.system(size:weight:)`는 고정 크기라 이 스케일링을 지원하지 않아서,
// UIFontMetrics로 시스템 폰트를 텍스트 스타일에 맞게 다시 스케일링한다(SwiftUI에는 커스텀 pt
// 값을 스케일링하는 대응 API가 없다 — 폰트 이름을 요구하는 Font.custom(relativeTo:)는 시스템
// 폰트에 쓰기엔 적합하지 않다).
enum Typography {
    // 28pt Bold — 페이지 대표 제목.
    static let largeTitle = font(size: 28, weight: .bold, relativeTo: .largeTitle)
    // 18pt Bold — 화면 제목(탭 상단 타이틀 등).
    static let screenTitle = font(size: 18, weight: .bold, relativeTo: .title3)
    // 20pt Bold — 섹션 제목.
    static let sectionTitle = font(size: 20, weight: .bold, relativeTo: .title2)
    // 19pt Bold — 한 화면에 여러 패널 제목이 반복되는 보고서용 섹션 제목.
    static let reportSectionTitle = font(size: 19, weight: .bold, relativeTo: .title3)
    // 16pt Semibold — 카드 제목.
    static let cardTitle = font(size: 16, weight: .semibold, relativeTo: .headline)
    // 17pt Regular — 본문.
    static let body = font(size: 17, weight: .regular, relativeTo: .body)
    // 18pt Semibold — 버튼(Primary). Secondary Button은 같은 크기에 .fontWeight(.medium)을 덧씌운다.
    static let button = font(size: 18, weight: .semibold, relativeTo: .body)
    // 15pt Regular — 보조 설명.
    static let secondary = font(size: 15, weight: .regular, relativeTo: .subheadline)
    // 13pt Regular — 일반 캡션. 수면 단계 차트 라벨만 아래 전용 토큰을 사용한다.
    static let caption = font(size: 13, weight: .regular, relativeTo: .caption)
    // 11pt Regular — 숫자 옆에 붙는 단위(시간/분/ms 등)처럼 caption보다 한 단계 더 작아야 하는 경우.
    static let caption2 = font(size: 11, weight: .regular, relativeTo: .caption2)
    // 12pt Regular — 수면 단계 차트의 행 라벨 전용.
    static let sleepStageLabel = font(size: 12, weight: .regular, relativeTo: .caption2)
    // 17pt Semibold — 수면 패턴 상단 날짜 전용.
    static let sleepDate = font(size: 17, weight: .semibold, relativeTo: .body)
    // 24pt Bold — 보고서의 강조 수치(평균 수면 시간·점수 등) 전용.
    static let bigStatValue = font(size: 24, weight: .bold, relativeTo: .title)
    // 21pt Bold — 스플래시 화면 태그라인 전용. screenTitle(18pt)을 재사용하지 않는 이유는, 그
    // 토큰을 스플래시용으로 바꾸면 실제 화면 제목으로 쓰는 다른 모든 곳도 같이 커지기 때문이다.
    static let splashTagline = font(size: 21, weight: .bold, relativeTo: .title3)
    // 9pt Regular — 오늘의 패턴 차트 x축 라벨 전용. 차트 안 촘촘한 라벨이라 다른 토큰과 달리
    // 스케일링 없이 고정 크기로 둔다 — 커지면 라벨이 겹치거나 잘린다.
    static let chartAxisLabel = Font.system(size: 9, weight: .regular)

    private static func font(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle) -> Font {
        let uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiFontWeight)
        let scaledFont = UIFontMetrics(forTextStyle: textStyle.uiFontTextStyle).scaledFont(for: uiFont)
        return Font(scaledFont)
    }
}

private extension Font.Weight {
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .black: .black
        case .bold: .bold
        case .heavy: .heavy
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .thin: .thin
        case .ultraLight: .ultraLight
        default: .regular
        }
    }
}

private extension Font.TextStyle {
    var uiFontTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
