import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        NavigationStack {
            List {
                // 일반 사용자는 약 등록·알림 설정·문의하기만 쓰면 되고, 분석용 화면들은 연구자/관리자
                // 대상이라 혼란만 준다 — 이 화면 자체는 사용자 요청으로 값을 바꿀 수 없는 역할이라
                // (docs/architecture.md), 여기서 감춰도 실제 권한과 어긋나지 않는다.
                if authViewModel.usesResearcherTerminology {
                    NavigationLink {
                        AnalysisSettingsView()
                    } label: {
                        Label("SDNN·rMSSD 분석", systemImage: "waveform.path.ecg")
                    }

                    NavigationLink {
                        CorrelationAnalysisView()
                    } label: {
                        Label("상관계수 분석", systemImage: "chart.xyaxis.line")
                    }

                    NavigationLink {
                        UnsolvedCasesView()
                    } label: {
                        Label("장기 미제 사건", systemImage: "magnifyingglass")
                    }
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

                if authViewModel.usesResearcherTerminology {
                    NavigationLink {
                        RRIntervalExportView()
                    } label: {
                        Label("RR 데이터 내보내기", systemImage: "waveform.path")
                    }
                }

                NavigationLink {
                    DeveloperContactView()
                } label: {
                    Label("개발자에게 문의하기", systemImage: "envelope")
                }

                #if DEBUG
                // 실제 rMSSD를 낮추거나 높일 수 없어서, 감지 로직은 건너뛰고 알림이 뜬 이후의
                // 흐름(탭 → 입력 화면 → 저장)만 확인해보는 디버그용 버튼 — 릴리스 빌드에는 없다.
                // 연구자도 이 버튼들은 볼 필요가 없어서 admin에게만 남긴다.
                if authViewModel.role == .admin {
                    Section("디버그") {
                        Button("rMSSD 낮음 알림 테스트") {
                            Task { await RMSSDThresholdMonitorService.shared.debugTriggerNotification(direction: .low) }
                        }
                        Button("rMSSD 높음 알림 테스트") {
                            Task { await RMSSDThresholdMonitorService.shared.debugTriggerNotification(direction: .high) }
                        }
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

private struct DeveloperContactView: View {
    private static let developerEmail = "kyoh@hutom.co.kr"

    @Environment(\.openURL) private var openURL
    @State private var message = ""
    @State private var isShowingMailError = false
    @FocusState private var isMessageFocused: Bool

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("문의 내용을 자세히 적어 주세요.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $message)
                        .focused($isMessageFocused)
                        .frame(minHeight: 280)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                Text("문의 내용")
            } footer: {
                Text("작성한 내용은 메일 앱으로 전달되며, 보내기 전 다시 확인할 수 있어요.")
            }

            Section {
                Button {
                    sendEmail()
                } label: {
                    Label("메일 앱에서 보내기", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(Typography.button)
                }
                .disabled(trimmedMessage.isEmpty)
            }
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("개발자에게 문의하기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") {
                    isMessageFocused = false
                }
            }
        }
        .alert("메일 앱을 열 수 없어요", isPresented: $isShowingMailError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("이 기기에서 메일을 보낼 수 있도록 메일 앱과 계정을 확인해 주세요.")
        }
    }

    private func sendEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.developerEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "MindProfiler 문의"),
            URLQueryItem(name: "body", value: trimmedMessage)
        ]

        guard let url = components.url else {
            isShowingMailError = true
            return
        }

        isMessageFocused = false
        openURL(url) { accepted in
            if !accepted {
                isShowingMailError = true
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
}
