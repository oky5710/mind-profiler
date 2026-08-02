import SwiftUI

// 타이포그래피의 단일 소스. 화면에서 `.font(.system(size: 17))`처럼 크기를 직접 지정하지 않고
// 반드시 이 토큰들을 사용한다 (docs/design-system.md의 Typography 섹션 참고).
enum Typography {
    // 34pt Bold — 페이지 대표 제목.
    static let largeTitle = Font.system(size: 28, weight: .bold)
    // 18pt Bold — 화면 제목(탭 상단 타이틀 등).
    static let screenTitle = Font.system(size: 18, weight: .bold)
    // 22pt Bold — 섹션 제목.
    static let sectionTitle = Font.system(size: 20, weight: .bold)
    // 19pt Bold — 한 화면에 여러 패널 제목이 반복되는 보고서용 섹션 제목.
    static let reportSectionTitle = Font.system(size: 19, weight: .bold)
    // 20pt Semibold — 카드 제목.
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    // 17pt Regular — 본문.
    static let body = Font.system(size: 17, weight: .regular)
    // 17pt Semibold — 버튼(Primary). Secondary Button은 같은 크기에 .fontWeight(.medium)을 덧씌운다.
    static let button = Font.system(size: 18, weight: .semibold)
    // 15pt Regular — 보조 설명.
    static let secondary = Font.system(size: 15, weight: .regular)
    // 13pt Regular — 일반 캡션. 수면 단계 차트 라벨만 아래 전용 토큰을 사용한다.
    static let caption = Font.system(size: 13, weight: .regular)
    // 12pt Regular — 수면 단계 차트의 행 라벨 전용.
    static let sleepStageLabel = Font.system(size: 12, weight: .regular)
    // 17pt Semibold — 수면 패턴 상단 날짜 전용.
    static let sleepDate = Font.system(size: 17, weight: .semibold)
    // 9pt Regular — 오늘의 패턴 차트 x축 라벨 전용.
    static let chartAxisLabel = Font.system(size: 9, weight: .regular)
}
