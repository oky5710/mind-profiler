import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AnalysisSettingsView()
                } label: {
                    Label("분석", systemImage: "waveform.path.ecg")
                }

                NavigationLink {
                    MedicationManagementView()
                } label: {
                    Label("약 등록", systemImage: "pills.fill")
                }

                NavigationLink {
                    ReminderListView()
                } label: {
                    Label("알림 설정", systemImage: "bell.badge")
                }

                NavigationLink {
                    RRIntervalExportView()
                } label: {
                    Label("RR 데이터 내보내기", systemImage: "waveform.path")
                }

                #if DEBUG
                // 실제 rMSSD를 낮추거나 높일 수 없어서, 감지 로직은 건너뛰고 알림이 뜬 이후의
                // 흐름(탭 → 입력 화면 → 저장)만 확인해보는 디버그용 버튼 — 릴리스 빌드에는 없다.
                Section("디버그") {
                    Button("rMSSD 낮음 알림 테스트") {
                        Task { await RMSSDThresholdMonitorService.shared.debugTriggerNotification(direction: .low) }
                    }
                    Button("rMSSD 높음 알림 테스트") {
                        Task { await RMSSDThresholdMonitorService.shared.debugTriggerNotification(direction: .high) }
                    }
                }
                #endif
            }
            .contentMargins(.top, 10, for: .scrollContent)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("설정").font(Typography.screenTitle)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
