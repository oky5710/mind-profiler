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
                    RRIntervalExportView()
                } label: {
                    Label("RR 데이터 내보내기", systemImage: "waveform.path")
                }
            }
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
