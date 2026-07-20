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
            }
            .navigationTitle("설정")
        }
    }
}

#Preview {
    SettingsView()
}
