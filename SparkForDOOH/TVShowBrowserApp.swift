//
//  SparkForDOOHApp.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI

@main
struct SparkForDOOHApp: App {
    init() {
        print("🚀 App launching...")
        
        // Initialize Sentry for crash reporting
        SentryService.shared.start()
        
        // Start initial heartbeat (will retry every 5 minutes until success)
        DispatchQueue.main.async {
            HeartbeatAPI.shared.startInitialHeartbeat()
        }
        
        // Clear old cache after a delay (protects Sentry and AdsCache)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            FileManagerHelper.shared.clearAppStorage()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            LandingGateView()
        }
    }
}

/// Simple landing gate that waits for initial heartbeat success before showing the app.
private struct LandingGateView: View {
    @State private var isReady = false
    @State private var didFail = false
    @State private var status: String = "Checking device status…"
    
    var body: some View {
        Group {
            if isReady {
                RootView()
            } else if didFail {
                ActivationView()
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(status)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                    Text("Will retry every 5 minutes if network/API fails.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
                .onAppear {
                    status = "Sending heartbeat…"
                    NotificationCenter.default.addObserver(
                        forName: .initialHeartbeatSucceeded,
                        object: nil,
                        queue: .main
                    ) { _ in
                        isReady = true
                    }
                    NotificationCenter.default.addObserver(
                        forName: .initialHeartbeatFailed,
                        object: nil,
                        queue: .main
                    ) { _ in
                        status = "Heartbeat failed. Redirecting to registration…"
                        didFail = true
                    }
                }
            }
        }
    }
}
