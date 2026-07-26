import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "house")
                }

            CalendarView()
                .tabItem {
                    Label("캘린더", systemImage: "calendar")
                }

            ReportView()
                .tabItem {
                    Label("보고서", systemImage: "doc.text.magnifyingglass")
                }

            HRVAnalysisView()
                .tabItem {
                    Label("오늘의 패턴", systemImage: "waveform.path.ecg")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
        // 앱 실행할 때마다 알림 설정을 다시 받아와 로컬 알림을 최신 상태로 재예약한다 — 실패해도
        // 조용히 넘어간다(알림 하나 때문에 앱 실행 자체를 막지 않는다).
        .task {
            await ReminderNotificationService.shared.resync()
        }
    }
}

#Preview {
    RootTabView()
        .environment(ToastCenter())
}
