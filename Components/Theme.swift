import SwiftUI

enum Theme {
    static let heart = Color(red: 0.9765, green: 0.3098, blue: 0.3882) // #F94F63
    static let mood = Color(red: 0.9608, green: 0.6196, blue: 0.0431) // #f59e0b
    static let coffee = Color(red: 0.5725, green: 0.2510, blue: 0.0549) // #92400e
    static let examRmssd = Color(red: 0.1333, green: 0.7725, blue: 0.3686) // #22c55e
    static let exercise = Color(red: 0.0863, green: 0.6392, blue: 0.2902) // #16a34a
    static let sleep = Color(red: 0.3882, green: 0.4000, blue: 0.9451) // #6366f1
    static let rmssd = Color(red: 0.5451, green: 0.3608, blue: 0.9647) // #8b5cf6
    static let gray7 = Color(red: 0.2157, green: 0.2549, blue: 0.3176) // #374151

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
