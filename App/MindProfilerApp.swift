//
//  MindProfilerApp.swift
//  MindProfiler
//

import GoogleSignIn
import SwiftUI

@main
struct MindProfilerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authViewModel = AuthViewModel()
    @State private var toastCenter = ToastCenter()
    @State private var rmssdThresholdAlertCenter = RMSSDThresholdAlertCenter()
    @State private var sleepUpdateNavigationCenter = SleepUpdateNavigationCenter()
    @State private var patternNavigationCenter = PatternNavigationCenter()
    @State private var isShowingSplash = true

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: GoogleSignInConfig.iOSClientID,
            serverClientID: GoogleSignInConfig.serverClientID
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isShowingSplash {
                    SplashView()
                        .transition(.opacity)
                } else if authViewModel.isAuthenticated {
                    if authViewModel.shouldShowOnboarding {
                        OnboardingView {
                            authViewModel.completeOnboarding()
                        }
                    } else {
                        RootTabView()
                    }
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
            .environment(rmssdThresholdAlertCenter)
            .environment(sleepUpdateNavigationCenter)
            .environment(patternNavigationCenter)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .task {
                guard isShowingSplash else { return }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.2)) {
                    isShowingSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    @State private var photo: Image?

    var body: some View {
        ZStack {
            Group {
                if let photo {
                    photo.resizable().scaledToFill()
                } else {
                    fallbackPhoto
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Text("Track your mind.\nFind the patterns.")
                .font(Typography.splashTagline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        }
        .task {
            if let image = await CatPhotoService.randomPhoto() {
                photo = Image(decorative: image, scale: 1)
            }
        }
    }

    private var fallbackPhoto: some View {
        Image("FallbackCatPhoto")
            .resizable()
            .scaledToFill()
    }
}
