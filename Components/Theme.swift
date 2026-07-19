import SwiftUI

enum Theme {
    // Radix UI Colors(radix-ui.com/colors) 팔레트로 통일 — 기존 Tailwind 기반 하드코딩 값들을
    // 색상 거리가 가장 가까운 Radix 스케일 단계로 교체했다.
    static let heart = Color(red: 0.8980, green: 0.2824, blue: 0.3020) // red-9 #e5484d
    static let mood = Color(red: 1.0000, green: 0.7294, blue: 0.0941) // amber-10 #ffba18
    static let coffee = Color(red: 0.6706, green: 0.3922, blue: 0.0000) // amber-11 #ab6400
    static let examRmssd = Color(red: 0.1882, green: 0.6431, blue: 0.4235) // green-9 #30a46c
    static let exercise = Color(red: 0.1686, green: 0.6039, blue: 0.4000) // green-10 #2b9a66
    static let sleep = Color(red: 0.2431, green: 0.3882, blue: 0.8667) // indigo-9 #3e63dd
    static let rmssd = Color(red: 0.4314, green: 0.3373, blue: 0.8118) // violet-9 #6e56cf
    static let holiday = Color(red: 0.8980, green: 0.2824, blue: 0.3020) // red-9 #e5484d
    static let vacation = Color(red: 0.9686, green: 0.4196, blue: 0.0824) // orange-9 #f76b15

    // Apple 표준 시스템 색상(HIG). 라이트/다크/대비 높음 4가지 모두 대응하는 값이라 UIKit 없이
    // Assets.xcassets의 컬러셋(SystemColors 그룹)으로 넣어뒀다 — 하드코딩된 단일 RGB가 아니라
    // 시스템 외형에 따라 자동으로 바뀐다.
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
}
