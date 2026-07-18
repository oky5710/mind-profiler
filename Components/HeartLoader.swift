import SwiftUI

struct HeartLoader: View {
    var height: CGFloat = 200

    private let heartColor = Color(red: 0.9765, green: 0.3098, blue: 0.3882) // #F94F63
    private let period: TimeInterval = 0.8

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let beat = (sin(t * 2 * .pi / period) + 1) / 2 // 0...1

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [heartColor.opacity(0.35), heartColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .scaleEffect(0.9 + beat * 0.15)
                    .opacity(0.8 + beat * 0.1)

                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(heartColor)
                    .scaleEffect(0.95 + beat * 0.17)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

#Preview {
    HeartLoader()
}
