//
//  MindProfilerApp.swift
//  MindProfiler
//

import GoogleSignIn
import SwiftUI

@main
struct MindProfilerApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var toastCenter = ToastCenter()

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: GoogleSignInConfig.iOSClientID,
            serverClientID: GoogleSignInConfig.serverClientID
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    RootTabView()
                } else {
                    LoginView()
                }
            }
            // 어느 화면이든 environment의 toastCenter.show(...)만 호출하면 여기 붙은 오버레이가
            // 화면 위쪽에 띄워준다. environment를 overlay 바깥에 적용해야 오버레이 내용도 상속받는다.
            .overlay(alignment: .top) {
                ToastOverlay()
                    .padding(.top, 8)
            }
            .environment(authViewModel)
            .environment(toastCenter)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            #if DEBUG
            // 디버그 전용 — 앱 UI에는 아무 것도 안 보이고, 어제 rMSSD를 필터 단계별로 비교해서
            // Xcode 콘솔에만 출력한다(HealthKitService.debugCompareRMSSDFiltersForYesterday 참고).
            .task {
                await HealthKitService.debugCompareRMSSDFiltersForYesterday()
            }
            #endif
        }
    }
}
