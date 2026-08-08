import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isShowingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    HRVGuideView()
                } label: {
                    Label("HRV 가이드", systemImage: "book.closed")
                }

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

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label("개인정보 처리방침", systemImage: "hand.raised")
                }

                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Label("이용약관", systemImage: "doc.text")
                }

                Section {
                    Button(role: .destructive) {
                        isShowingSignOutConfirmation = true
                    } label: {
                        Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
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
                        NavigationLink("회복 지수 분포 확인") {
                            RecoveryScoreDistributionView()
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
            .confirmationDialog(
                "로그아웃 하시겠어요?",
                isPresented: $isShowingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("로그아웃", role: .destructive) {
                    authViewModel.signOut()
                }
                Button("취소", role: .cancel) {}
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

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("최종 업데이트: 2026년 8월 8일")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                paragraph("Mind Profiler(이하 \"앱\")는 이용자의 개인정보를 중요하게 생각하며, 관련 법령을 준수합니다. 본 개인정보 처리방침은 앱에서 수집하는 정보와 이용 목적, 보관 방법 및 이용자의 권리를 안내하기 위해 작성되었습니다.")
            }

            policySection("1. 수집하는 정보") {
                paragraph("앱은 다음 정보를 수집하거나 접근할 수 있습니다.")
                subheading("① 계정 정보")
                bullets([
                    "Google 로그인 계정 정보",
                    "이메일 주소",
                    "사용자 식별을 위한 고유 ID",
                ])
                subheading("② 건강 정보 (HealthKit)")
                paragraph("사용자가 권한을 허용한 경우에만 다음 정보를 읽습니다.")
                bullets([
                    "심박변이(HRV)",
                    "심박수",
                    "수면 데이터",
                    "운동 데이터",
                    "기타 사용자가 명시적으로 접근을 허용한 건강 데이터",
                ])
                paragraph("HealthKit 데이터는 사용자의 건강 패턴 분석 및 시각화를 위해서만 사용됩니다.")
                subheading("③ 사용자가 직접 입력한 정보")
                bullets([
                    "기분 기록",
                    "복용 약 정보",
                    "메모",
                    "기타 사용자가 직접 입력한 정보",
                ])
                subheading("④ 기술 정보")
                paragraph("앱의 안정적인 운영을 위해 다음 정보가 수집될 수 있습니다.")
                bullets([
                    "앱 버전",
                    "운영체제 버전",
                    "오류 로그(있는 경우)",
                ])
            }

            policySection("2. 개인정보의 이용 목적") {
                paragraph("수집한 정보는 다음 목적으로만 이용합니다.")
                bullets([
                    "개인 맞춤형 건강 패턴 분석",
                    "회복 지수 및 통계 제공",
                    "차트 및 보고서 생성",
                    "사용자 설정 저장",
                    "앱 오류 수정 및 서비스 개선",
                ])
            }

            policySection("3. HealthKit 데이터 이용") {
                paragraph("HealthKit 데이터는 Apple의 HealthKit 정책을 준수하여 처리됩니다.")
                bullets([
                    "사용자의 명시적인 동의가 있는 경우에만 접근합니다.",
                    "광고 또는 마케팅 목적으로 사용하지 않습니다.",
                    "제3자에게 판매하거나 제공하지 않습니다.",
                    "사용자의 건강 정보를 광고에 활용하지 않습니다.",
                    "**HealthKit에서 읽은 건강 데이터는 사용자의 기기 내에서만 분석됩니다.**",
                    "**HealthKit 데이터는 당사 서버로 전송하거나 저장하지 않습니다.**",
                    "**회복 지수, 패턴 분석 등은 사용자의 기기에서 로컬로 계산되며, 사용자의 명시적인 동의 없이 외부로 전송되지 않습니다.**",
                ])
            }

            policySection("4. 개인정보의 보관") {
                paragraph("개인정보는 서비스 제공에 필요한 기간 동안만 보관합니다.")
                paragraph("사용자가 계정을 삭제하거나 삭제를 요청하는 경우 관련 법령에 따라 보관이 필요한 정보를 제외하고 지체 없이 삭제합니다.")
            }

            policySection("5. 개인정보의 제3자 제공") {
                paragraph("앱은 이용자의 개인정보를 판매하거나 제3자에게 제공하지 않습니다.")
                paragraph("다만 다음의 경우에는 예외로 합니다.")
                bullets([
                    "이용자의 별도 동의가 있는 경우",
                    "법령에 따른 요청이 있는 경우",
                ])
            }

            policySection("6. 개인정보 처리 위탁") {
                paragraph("서비스 운영을 위해 일부 업무를 외부 서비스에 위탁할 수 있습니다.")
                subheading("예시")
                bullets([
                    "Google 로그인",
                    "클라우드 서버",
                    "오류 분석 서비스",
                ])
                paragraph("위탁업체가 변경되는 경우 본 개인정보 처리방침을 통해 안내합니다.")
            }

            policySection("7. 이용자의 권리") {
                paragraph("이용자는 언제든지 다음 권리를 행사할 수 있습니다.")
                bullets([
                    "개인정보 열람",
                    "개인정보 수정",
                    "개인정보 삭제 요청",
                    "HealthKit 권한 철회",
                ])
                paragraph("HealthKit 권한은 iPhone의 **설정 > 건강 > 데이터 접근 및 기기**에서 변경할 수 있습니다.")
            }

            policySection("8. 의료 관련 안내") {
                paragraph("본 앱은 건강 관리 및 개인 기록을 위한 서비스입니다.")
                paragraph("앱에서 제공하는 분석 결과와 회복 지수는 참고용 정보이며 의료진의 진단, 치료 또는 의학적 판단을 대체하지 않습니다.")
                paragraph("건강에 이상이 있다고 판단되는 경우 반드시 의료 전문가와 상담하시기 바랍니다.")
            }

            policySection("9. 개인정보 보호") {
                paragraph("앱은 개인정보 보호를 위해 합리적인 기술적·관리적 보호조치를 적용합니다.")
            }

            policySection("10. 개인정보 처리방침 변경") {
                paragraph("본 개인정보 처리방침은 관련 법령 또는 서비스 변경에 따라 수정될 수 있습니다.")
                paragraph("중요한 변경 사항이 있는 경우 앱 또는 홈페이지를 통해 안내합니다.")
            }

            policySection("11. 문의") {
                paragraph("개인정보 처리와 관련한 문의는 아래 연락처로 문의해 주시기 바랍니다.")
                Link("이메일: oky5710@gmail.com", destination: URL(string: "mailto:oky5710@gmail.com")!)
            }
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .navigationTitle("개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }

}

// PrivacyPolicyView·TermsOfServiceView가 같이 쓰는, 법률 문서 화면 전용 레이아웃 조각.
private func policySection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    Section {
        content()
    } header: {
        Text(title)
    }
}

private func subheading(_ text: String) -> some View {
    Text(text).font(.subheadline.bold())
}

private func paragraph(_ text: String) -> some View {
    Text(LocalizedStringKey(text))
}

private func bullets(_ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        ForEach(items, id: \.self) { item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                paragraph(item)
            }
        }
    }
}

private struct HRVGuideView: View {
    var body: some View {
        List {
            policySection("🌿 HRV란?") {
                paragraph("HRV(Heart Rate Variability)는 심장 박동 사이 시간(RR 간격)이 얼마나 변화하는지를 나타내는 지표입니다.")
                paragraph("예를 들어 심박수가 60bpm이라고 해서 매번 정확히 1초마다 뛰는 것은 아닙니다.")
                bullets(["980ms", "1020ms", "995ms", "1015ms"])
                paragraph("처럼 조금씩 달라집니다.")
                paragraph("이러한 변화의 크기를 HRV라고 합니다.")
                paragraph("HRV는 자율신경계의 영향을 받으며, 수면, 운동, 스트레스, 질병, 음주, 카페인 등 다양한 요인에 의해 달라질 수 있습니다.")
                paragraph("중요한 것은 다른 사람과 비교하는 것보다 자신의 평소 패턴과 비교하는 것입니다.")
            }

            policySection("❤️ rMSSD란?") {
                paragraph("rMSSD(Root Mean Square of Successive Differences)는 HRV를 계산하는 여러 방법 중 하나입니다.")
                paragraph("인접한 심장 박동 간격(RR interval)의 차이를 이용하여 계산하며, 짧은 시간(약 1~5분) 측정에서도 비교적 안정적으로 사용할 수 있어 스마트워치에서 가장 많이 사용하는 HRV 지표 중 하나입니다.")
                paragraph("일반적으로 rMSSD는 부교감신경 활동과 관련된 변화를 잘 반영하는 것으로 알려져 있습니다.")
            }

            policySection("📊 회복지수는 어떻게 계산되나요?") {
                paragraph("회복지수는 절대적인 건강 점수가 아닙니다.")
                paragraph("최근 30일 동안의 나의 데이터를 기준으로 오늘이 평소보다 얼마나 회복되었는지를 보여주는 개인화된 지표입니다.")
                paragraph("계산 과정은 다음과 같습니다.")
                bullets([
                    "1. 수면, 오전, 오후로 시간을 구분합니다.",
                    "2. 각 시간대에서 최근 30일 rMSSD 중앙값과 오늘의 중앙값을 비교합니다.",
                    "3. MAD(Median Absolute Deviation)를 이용하여 평소와의 차이를 계산합니다.",
                    "4. 각 시간대의 결과를 통합하여 회복지수를 계산합니다.",
                ])
                paragraph("회복지수는 다른 사람과 비교하기 위한 점수가 아니라 자신의 평소 상태와 비교하기 위한 점수입니다.")
            }

            policySection("📈 HRV Trend 읽는 법") {
                paragraph("하루 동안 HRV는 계속 변합니다.")
                paragraph("높다고 항상 좋은 것도 아니고, 낮다고 항상 나쁜 것도 아닙니다.")
                paragraph("HRV는 다음과 같은 영향을 받을 수 있습니다.")
                bullets(["수면", "운동", "식사", "업무", "스트레스", "휴식", "질병", "음주"])
                paragraph("중요한 것은 하루의 한 번 측정이 아니라 장기적인 패턴입니다.")
                paragraph("최근 며칠 또는 몇 주 동안 어떤 변화가 이어지는지 함께 살펴보는 것이 좋습니다.")
            }

            policySection("🌙 수면과 HRV") {
                paragraph("수면은 HRV에 가장 큰 영향을 주는 요인 중 하나입니다.")
                paragraph("충분한 수면을 취하면 다음 날 HRV가 높게 나타나는 경우가 많지만, 모든 사람에게 항상 같은 결과가 나타나는 것은 아닙니다.")
                paragraph("다음과 같은 요소들이 함께 영향을 줄 수 있습니다.")
                bullets(["수면 시간", "수면 연속성", "깊은 수면", "REM 수면", "수면 중 각성", "취침 시간"])
                paragraph("HRV는 수면의 질을 이해하는 하나의 참고 자료로 활용할 수 있습니다.")
            }

            policySection("💪 운동과 HRV") {
                paragraph("운동 직후에는 HRV가 일시적으로 낮아질 수 있습니다.")
                paragraph("이는 몸이 운동에 적응하고 회복하는 과정에서 자연스럽게 나타날 수 있는 변화입니다.")
                paragraph("반대로 충분히 회복한 이후에는 평소보다 높은 HRV가 나타나는 경우도 있습니다.")
                paragraph("운동 효과를 평가할 때는 하루의 수치보다 며칠간의 변화와 함께 살펴보는 것이 좋습니다.")
            }

            policySection("🧠 스트레스와 HRV") {
                paragraph("심리적 스트레스는 HRV에 영향을 줄 수 있습니다.")
                paragraph("하지만 HRV만으로 스트레스를 정확하게 판단할 수는 없습니다.")
                paragraph("업무, 시험, 발표뿐 아니라")
                bullets(["감기", "통증", "수면 부족", "탈수", "카페인", "운동"])
                paragraph("등 다양한 요인도 HRV에 영향을 줄 수 있습니다.")
                paragraph("따라서 HRV는 스트레스를 진단하는 도구가 아니라 몸의 변화를 이해하기 위한 참고 지표로 사용하는 것이 좋습니다.")
            }

            policySection("⌚ Apple Watch는 어떻게 측정하나요?") {
                paragraph("Apple Watch는 광학 심박 센서를 이용하여 심박을 측정합니다.")
                paragraph("일부 측정에서는 심장 박동 간격(RR interval)을 이용하여 HRV를 계산합니다.")
                paragraph("Mind Profiler는 Apple Health의 Heartbeat Series 데이터를 이용하여 rMSSD를 계산합니다.")
                paragraph("측정 환경이나 센서 상태에 따라 일부 측정은 제외될 수 있으며, 손목 착용 상태나 움직임에 따라서도 결과가 달라질 수 있습니다.")
            }
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .navigationTitle("HRV 가이드")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TermsOfServiceView: View {
    var body: some View {
        List {
            Section {
                Text("최종 업데이트: 2026년 8월 8일")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                paragraph("본 이용약관은 Mind Profiler(이하 \"앱\")의 이용과 관련하여 이용자와 운영자 간의 권리, 의무 및 책임사항을 규정합니다.")
            }

            policySection("제1조 (목적)") {
                paragraph("본 약관은 이용자가 앱을 이용함에 있어 필요한 사항을 규정함을 목적으로 합니다.")
            }

            policySection("제2조 (서비스 내용)") {
                paragraph("앱은 다음과 같은 기능을 제공합니다.")
                bullets([
                    "HealthKit 데이터를 활용한 건강 패턴 분석",
                    "회복 지수 및 통계 제공",
                    "수면, 심박변이(HRV), 운동 등 건강 데이터 시각화",
                    "기분, 약 복용, 메모 등 개인 기록 관리",
                    "건강 패턴 보고서 생성",
                ])
                paragraph("서비스 내용은 운영 정책에 따라 변경될 수 있습니다.")
            }

            policySection("제3조 (회원가입 및 로그인)") {
                paragraph("이용자는 지원되는 로그인 방식을 통해 서비스를 이용할 수 있습니다.")
                paragraph("이용자는 본인의 계정을 직접 관리해야 하며, 계정 관리 소홀로 발생한 문제에 대한 책임은 이용자에게 있습니다.")
            }

            policySection("제4조 (HealthKit 이용)") {
                paragraph("앱은 사용자의 동의가 있는 경우에만 Apple HealthKit 데이터에 접근합니다.")
                paragraph("HealthKit 데이터는 사용자의 건강 패턴 분석을 위해서만 이용되며,")
                bullets([
                    "광고에 이용되지 않습니다.",
                    "제3자에게 판매되지 않습니다.",
                    "사용자의 명시적인 동의 없이 외부로 전송되지 않습니다.",
                    "사용자의 기기 내에서만 분석됩니다.",
                ])
            }

            policySection("제5조 (이용자의 의무)") {
                paragraph("이용자는 다음 행위를 해서는 안 됩니다.")
                bullets([
                    "다른 사람의 계정을 사용하는 행위",
                    "서비스 운영을 방해하는 행위",
                    "앱을 불법적인 목적으로 이용하는 행위",
                    "관련 법령을 위반하는 행위",
                ])
            }

            policySection("제6조 (서비스 변경 및 중단)") {
                paragraph("운영자는 서비스 개선 또는 시스템 점검을 위해 서비스의 일부 또는 전부를 변경하거나 일시적으로 중단할 수 있습니다.")
                paragraph("서비스 변경 또는 중단이 필요한 경우 가능한 범위에서 사전에 안내합니다.")
            }

            policySection("제7조 (면책사항)") {
                paragraph("앱에서 제공하는 분석 결과, 회복 지수 및 각종 통계는 건강 관리를 위한 참고 자료입니다.")
                paragraph("앱은 의료기기가 아니며, 의사의 진단·치료 또는 전문적인 의료 판단을 대체하지 않습니다.")
                paragraph("이용자는 자신의 건강 상태와 관련된 중요한 의사결정을 할 때 반드시 의료 전문가와 상담해야 합니다.")
                paragraph("운영자는 이용자가 앱의 분석 결과만을 근거로 내린 판단으로 인해 발생한 손해에 대하여 관련 법령에서 허용하는 범위 내에서 책임을 지지 않습니다.")
            }

            policySection("제8조 (지식재산권)") {
                paragraph("앱의 디자인, 코드, 로고 및 콘텐츠에 대한 저작권 및 지식재산권은 운영자에게 있습니다.")
                paragraph("관련 법령에서 허용하는 범위를 제외하고 운영자의 사전 동의 없이 복제, 배포 또는 상업적으로 이용할 수 없습니다.")
            }

            policySection("제9조 (약관의 변경)") {
                paragraph("운영자는 관련 법령 또는 서비스 변경에 따라 본 약관을 수정할 수 있습니다.")
                paragraph("중요한 변경 사항은 앱 또는 홈페이지를 통해 안내합니다.")
            }

            policySection("제10조 (문의)") {
                paragraph("서비스 이용과 관련한 문의는 아래 연락처로 문의해 주시기 바랍니다.")
                Link("이메일: oky5710@gmail.com", destination: URL(string: "mailto:oky5710@gmail.com")!)
            }
        }
        .contentMargins(.top, 10, for: .scrollContent)
        .navigationTitle("이용약관")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
}
