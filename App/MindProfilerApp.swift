//
//  MindProfilerApp.swift
//  MindProfiler
//

import GoogleSignIn
import SwiftUI

@main
struct MindProfilerApp: App {
    @State private var authViewModel = AuthViewModel()

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
            .environment(authViewModel)
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
