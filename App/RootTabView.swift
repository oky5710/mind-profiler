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

            StatisticsView()
                .tabItem {
                    Label("통계", systemImage: "chart.line.uptrend.xyaxis")
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
    }
}

#Preview {
    RootTabView()
}
