import SwiftUI

// 화면 어디서든 공통으로 띄우는 짧은 안내 메시지. 정보/성공/에러 세 유형이 배경은 같고
// 아이콘 색으로만 구분된다 — 앱 전체에서 톤이 흔들리지 않게 하기 위함.
enum ToastType {
    case info
    case success
    case error

    var iconName: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .info: Theme.systemBlue
        case .success: Theme.systemGreen
        case .error: Theme.systemRed
        }
    }
}

// MindProfilerApp에서 environment로 주입해 앱 전역에서 하나만 공유한다 — 어느 화면에서든
// `@Environment(ToastCenter.self)`로 꺼내 `toastCenter.show(...)`만 호출하면 된다.
@Observable
final class ToastCenter {
    private(set) var message: String?
    private(set) var type: ToastType = .info
    // 연달아 show()가 호출돼도 가장 최근 호출만 사라지게 토큰으로 구분한다 — 안 그러면 먼저
    // 예약된 delay가 나중 메시지를 지워버릴 수 있다.
    private var dismissToken: UUID?

    func show(_ message: String, type: ToastType = .info, duration: Duration = .milliseconds(900)) {
        let token = UUID()
        dismissToken = token
        withAnimation(.easeOut(duration: 0.15)) {
            self.message = message
            self.type = type
        }
        Task {
            try? await Task.sleep(for: duration)
            guard dismissToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.message = nil
            }
        }
    }
}

// 앱 루트에 한 번만 `.overlay(alignment: .top) { ToastOverlay() }`로 붙여두면 어느 화면에서
// show()를 호출하든 화면 위쪽에 떴다가 자동으로 사라진다.
struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toastCenter

    var body: some View {
        if let message = toastCenter.message {
            HStack(spacing: 6) {
                Image(systemName: toastCenter.type.iconName)
                    .foregroundStyle(toastCenter.type.iconColor)
                Text(message)
                    .foregroundStyle(.white)
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.75), in: Capsule())
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}
