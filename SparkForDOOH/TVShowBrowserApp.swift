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
        
        DispatchQueue.main.async {
            Task {
                await TVRemoteConfigService.fetchConfigUntilSuccess()
                SentryService.shared.start()
                await MainActor.run {
                    SentryService.shared.syncUserContextIfActivated()
                    SentryService.shared.track(
                        SentryAnalyticsEvent.tvConfigLoaded,
                        attributes: ["activation_host": TVRemoteConfigStore.shared.environmentLabel]
                    )
                    SentryService.shared.breadcrumb(
                        category: "lifecycle",
                        message: "tv_config_ready",
                        data: [:]
                    )
                }
                HeartbeatAPI.shared.startInitialHeartbeat()
            }
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
    @State private var tvConfigReady = false
    @State private var isReady = false
    @State private var didFail = false
    @State private var status: String = "Checking device status…"
    @State private var hasPersistedActivation: Bool = AppRootViewModel.isDeviceActivated()
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            Group {
                if !tvConfigReady {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Loading configuration…")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                } else if isReady || hasPersistedActivation {
                    RootView()
                } else if didFail {
                    ActivationView {
                        // Activation succeeded; proceed to app.
                        didFail = false
                        isReady = true
                        hasPersistedActivation = true
                    }
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
                            hasPersistedActivation = AppRootViewModel.isDeviceActivated()
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
                    .onChange(of: networkMonitor.isConnected) { connected in
                        if connected && !isReady && !hasPersistedActivation {
                            // If we were showing the offline screen, move back to the gate and retry.
                            didFail = false
                            status = "Connection restored. Retrying heartbeat…"
                            HeartbeatAPI.shared.startInitialHeartbeat()
                        }
                    }
                    .onAppear {
                        // If already activated from a prior run, skip heartbeat entirely.
                        if hasPersistedActivation {
                            isReady = true
                        }
                    }
                }
            }
            
            // Only show offline overlay while gating/activation and not already activated.
            if tvConfigReady,
               !networkMonitor.isConnected && !isReady && !hasPersistedActivation {
                ConnectionLostView()
                    .transition(.opacity)
            }
        }
        .task {
            await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
            tvConfigReady = true
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !isReady {
                NetworkMonitor.shared.refreshConnectivity()
            }
        }
    }
}
