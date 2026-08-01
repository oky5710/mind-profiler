import SwiftUI

enum Theme {
    // MARK: - Brand

    // 앱의 대표 브랜드 컬러.
    // 버튼, 선택 상태, 토글, 링크, 포커스 등 인터랙션 요소에 사용한다.
    // 개별 건강 지표를 표현하는 데이터 색으로는 사용하지 않는다.
    static let primary = Color(
        red: 0.5882,
        green: 0.5137,
        blue: 0.9255
    ) // #9683EC

    // MARK: - Indicator Colors

    // 지표 색은 Radix UI Colors(radix-ui.com/colors) 팔레트로 통일한다.
    // 새로운 지표 색이 필요하면 임의의 HEX를 추가하지 않고 Radix 스케일에서 선택한다.
    //
    // 일반적으로:
    // - 6~8단계: 테두리와 은은한 구분
    // - 9단계: 대표색, 차트 선, 데이터 포인트
    // - 10단계: 강조 또는 hover
    // - 11~12단계: 색이 들어간 텍스트
    //
    // Primary는 브랜드 색이고 아래 색들은 데이터 종류를 나타내는 지표 색이다.

    static let heart = Color(
        red: 0.8980,
        green: 0.2745,
        blue: 0.4000
    ) // ruby-9 #e54666

    static let mood = Color(
        red: 1.0000,
        green: 0.7725,
        blue: 0.2392
    ) // amber-9 #ffc53d

    static let coffee = Color(
        red: 0.9686,
        green: 0.4078,
        blue: 0.0314
    ) // orange-10 #f76808

    static let examRmssd = Color(
        red: 0.1882,
        green: 0.6431,
        blue: 0.4235
    ) // green-9 #30a46c

    static let exercise = Color(
        red: 0.1608,
        green: 0.6392,
        blue: 0.5137
    ) // jade-9 #29a383

    static let sleep = Color(
        red: 0.2431,
        green: 0.3882,
        blue: 0.8667
    ) // indigo-9 #3e63dd

    // HealthKit 원시 박동 데이터에서 계산한 rMSSD.
    // 차트 선과 데이터 포인트처럼 명확한 식별이 필요한 곳에 사용한다.
    static let rmssd = Color(
        red: 0.3569,
        green: 0.3569,
        blue: 0.8392
    ) // iris-9 #5b5bd6

    // rMSSD가 최근 30일 중앙값의 150% 이상으로 급격히 높아진 지점(원 테두리·다이아몬드) 전용 색.
    // SwiftUI 기본 `.green`은 너무 쨍하고 촌스러워서, 사용자가 직접 지정한 채도 낮춘 초록으로 바꿨다.
    static let rmssdHigh = Color(
        red: 0.1922,
        green: 0.6863,
        blue: 0.4549
    ) // #31af74

    // 오늘의 패턴 시간별 모드, 간트 차트 아래 아이콘 레인의 약복용 마커 전용 색.
    // 커피(orange)·이벤트(blue)와 겹치지 않으면서 브랜드 보라(primary)와도 구분되도록 핑크 계열로.
    static let medication = Color(
        red: 0.8392,
        green: 0.2510,
        blue: 0.6235
    ) // pink-9 #d6409f

    // 월별 캔들스틱 박스(1Q~3Q) 전용 색.
    // rmssd와 같은 Iris 계열을 사용해 의미적 연결을 유지한다.
    // 넓은 면적을 채워도 무겁지 않도록 rmssd보다 옅은 6단계를 사용한다.
    static let rmssdRange = Color(
        red: 0.7961,
        green: 0.8039,
        blue: 1.0000
    ) // iris-6 #cbcdff

    static let holiday = Color(
        red: 0.8980,
        green: 0.2745,
        blue: 0.4000
    ) // ruby-9 #e54666

    static let vacation = Color(
        red: 0.9686,
        green: 0.4196,
        blue: 0.0824
    ) // orange-9 #f76b15

    // MARK: - Sleep Stage Colors

    // 수면 단계 도넛 차트 전용 카테고리컬 팔레트.
    //
    // dataviz 스킬의 검증된 기본 팔레트인
    // 블루 / 그린 / 마젠타 / 옐로 순서를 그대로 사용한다.
    // 처음 4개 색상은 CVD 전 쌍 검증을 통과했다.
    //
    // 수면 단계는 서로 구분되는 카테고리가 필요하므로
    // 일반 지표용 Radix 팔레트와 별도로 관리한다.

    static let sleepStageDeep = Color(
        red: 0.1647,
        green: 0.4706,
        blue: 0.8392
    ) // blue #2a78d6

    static let sleepStageREM = Color(
        red: 0.0000,
        green: 0.5137,
        blue: 0.0000
    ) // green #008300

    static let sleepStageCore = Color(
        red: 0.9098,
        green: 0.4824,
        blue: 0.6431
    ) // magenta #e87ba4

    static let sleepStageUnspecified = Color(
        red: 0.9294,
        green: 0.6314,
        blue: 0.0000
    ) // yellow #eda100

    // MARK: - Apple System Colors

    // Apple HIG 표준 시스템 색상.
    //
    // 라이트 모드, 다크 모드, 대비 높음 환경에 맞춰 자동으로 변경된다.
    // UIKit에 직접 의존하지 않도록 Assets.xcassets의
    // SystemColors 그룹에 컬러셋으로 등록해 사용한다.
    //
    // 지표 색이 아닌 일반 UI, 임시 상태, 참고선 등에 사용한다.

    static let systemRed = Color("SystemRed")
    static let systemOrange = Color("SystemOrange")
    static let systemYellow = Color("SystemYellow")
    static let systemGreen = Color("SystemGreen")
    static let systemMint = Color("SystemMint")
    static let systemTeal = Color("SystemTeal")
    static let systemCyan = Color("SystemCyan")
    static let systemBlue = Color("SystemBlue")
    static let systemIndigo = Color("SystemIndigo")
    static let systemPurple = Color("SystemPurple")
    static let systemPink = Color("SystemPink")
    static let systemBrown = Color("SystemBrown")

    static let systemGray = Color("SystemGray")
    static let systemGray2 = Color("SystemGray2")
    static let systemGray3 = Color("SystemGray3")
    static let systemGray4 = Color("SystemGray4")
    static let systemGray5 = Color("SystemGray5")
    static let systemGray6 = Color("SystemGray6")
    
    // MARK: - Brand Scale

    static let primary50 = Color(
        red: 0.9412,
        green: 0.9294,
        blue: 0.9843
    ) // #F0EDFB

    static let primary100 = Color(
        red: 0.8784,
        green: 0.8627,
        blue: 0.9686
    ) // #E0DCF7

    static let primary200 = Color(
        red: 0.8196,
        green: 0.7922,
        blue: 0.9569
    ) // #D1CAF4

    static let primary300 = Color(
        red: 0.7569,
        green: 0.7255,
        blue: 0.9412
    ) // #C1B9F0

    static let primary400 = Color(
        red: 0.6980,
        green: 0.6588,
        blue: 0.9255
    ) // #B2A8EC

    static let primary500 = Color(
        red: 0.6392,
        green: 0.5882,
        blue: 0.9098
    ) // #A396E8

    // primary(600 사이의 브랜드 메인 컬러)는 파일 상단에 이미 선언돼 있다 (#9683EC).

    static let primary600 = Color(
        red: 0.5804,
        green: 0.5137,
        blue: 0.8980
    ) // #9483E5

    static let primary700 = Color(
        red: 0.5216,
        green: 0.4510,
        blue: 0.8863
    ) // #8573E2

    static let primary800 = Color(
        red: 0.4588,
        green: 0.3804,
        blue: 0.8706
    ) // #7561DE

    static let primary900 = Color(
        red: 0.4000,
        green: 0.3137,
        blue: 0.8588
    ) // #6650DB
}
