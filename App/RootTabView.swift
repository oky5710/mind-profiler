import SwiftUI

struct RootTabView: View {
    @Environment(RMSSDThresholdAlertCenter.self) private var rmssdThresholdAlertCenter
    @Environment(SleepUpdateNavigationCenter.self) private var sleepUpdateNavigationCenter
    @Environment(PatternNavigationCenter.self) private var patternNavigationCenter
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .home
    @State private var homeRefreshRequestID: UUID?
    @State private var patternOpenSleepRequestID: UUID?
    @State private var patternRequestedSleepDate: Date?
    @State private var patternOpenHRVTrendRequestID: UUID?

    private enum RootTab: Hashable {
        case home, calendar, report, pattern, settings
    }

    var body: some View {
        @Bindable var rmssdThresholdAlertCenter = rmssdThresholdAlertCenter
        TabView(selection: $selectedTab) {
            HomeView(refreshRequestID: homeRefreshRequestID)
                .tag(RootTab.home)
                .tabItem {
                    Label("홈", systemImage: "house")
                }

            HRVAnalysisView(
                openSleepRequestID: patternOpenSleepRequestID,
                requestedSleepDate: patternRequestedSleepDate,
                openHRVTrendRequestID: patternOpenHRVTrendRequestID
            )
                .tag(RootTab.pattern)
                .tabItem {
                    Label("오늘의 패턴", systemImage: "waveform.path.ecg")
                }

            CalendarView()
                .tag(RootTab.calendar)
                .tabItem {
                    Label("캘린더", systemImage: "calendar")
                }

            ReportView()
                .tag(RootTab.report)
                .tabItem {
                    Label("보고서", systemImage: "doc.text.magnifyingglass")
                }

            SettingsView()
                .tag(RootTab.settings)
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
        // 앱 실행할 때마다 알림 설정을 다시 받아와 로컬 알림을 최신 상태로 재예약한다 — 실패해도
        // 조용히 넘어간다(알림 하나 때문에 앱 실행 자체를 막지 않는다).
        .task {
            _ = try? await ReminderNotificationService.shared.resync()
        }
        // 14일치만 미리 예약하므로 앱이 종료되지 않은 채 오래 백그라운드에 있었더라도, 다시
        // 활성화되는 순간 예약 창을 오늘 기준으로 앞으로 밀어 채운다.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                _ = try? await ReminderNotificationService.shared.resync()
            }
        }
        .onChange(of: sleepUpdateNavigationCenter.openHomeRequestID) { _, requestID in
            guard requestID != nil else { return }
            selectedTab = .home
            homeRefreshRequestID = UUID()
            sleepUpdateNavigationCenter.consumeOpenHomeRequest()
        }
        .onChange(of: patternNavigationCenter.openSleepRequestID) { _, requestID in
            guard requestID != nil else { return }
            selectedTab = .pattern
            patternRequestedSleepDate = patternNavigationCenter.requestedSleepDate
            patternOpenSleepRequestID = UUID()
            patternNavigationCenter.consumeOpenSleepRequest()
        }
        .onChange(of: patternNavigationCenter.openHRVTrendRequestID) { _, requestID in
            guard requestID != nil else { return }
            selectedTab = .pattern
            patternOpenHRVTrendRequestID = UUID()
            patternNavigationCenter.consumeOpenHRVTrendRequest()
        }
        .fullScreenCover(item: $rmssdThresholdAlertCenter.pendingEvent) { pendingEvent in
            RMSSDEventEntryForm(pendingEvent: pendingEvent) {
                rmssdThresholdAlertCenter.pendingEvent = nil
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(ToastCenter())
        .environment(RMSSDThresholdAlertCenter())
        .environment(SleepUpdateNavigationCenter())
        .environment(PatternNavigationCenter())
}
