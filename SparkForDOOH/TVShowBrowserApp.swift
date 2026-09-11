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
                    SentryService.shared.attachDeviceContext(
                        environment: TVRemoteConfigStore.shared.environmentLabel
                    )
                    SentryService.shared.syncUserContextIfActivated()
                    SentryService.shared.track(
                        SentryAnalyticsEvent.appLaunch,
                        attributes: [
                            "config_key": TVRemoteConfigStore.shared.selectedKey,
                            "device_activated": AppRootViewModel.isDeviceActivated() ? "true" : "false"
                        ]
                    )
                    SentryService.shared.breadcrumb(category: "lifecycle", message: "app_launch", data: [:])
                    SentryService.shared.breadcrumb(
                        category: "lifecycle",
                        message: "tv_config_ready",
                        data: [:]
                    )
                    #if DEBUG
                    if CommandLine.arguments.contains("--sentry-crash-test") {
                        let crashKey = "com.doceree.sparkfordooh.debug.sentryCrashTestTriggered"
                        if !UserDefaults.standard.bool(forKey: crashKey) {
                            UserDefaults.standard.set(true, forKey: crashKey)
                            SentryService.shared.breadcrumb(
                                category: "debug",
                                message: "sentry_crash_test_requested",
                                data: [:]
                            )
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                SentryService.shared.triggerTestCrashForPOC()
                            }
                        } else {
                            print("🧪 Sentry crash test already triggered once; skipping to allow crash upload.")
                        }
                    }
                    #endif
                }
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
                .remoteMenuExitConfirmation()
        }
    }
}

/// Landing gate:
/// - No poll `secureKey` → first-time activation (no heartbeat)
/// - Has `secureKey` → one heartbeat on launch (ACTIVE required), then 20‑min timer
private struct LandingGateView: View {
    @State private var tvConfigReady = false
    @State private var isReady = false
    @State private var showActivation = false
    @State private var status: String = "Checking device status…"
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    private var hasSecureKey: Bool { AppRootViewModel.hasSavedSecureKey() }
    
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
                } else if isReady {
                    RootView()
                } else if showActivation {
                    ActivationView {
                        showActivation = false
                        isReady = true
                        HeartbeatAPI.shared.startHeartbeat()
                    }
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(status)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Waiting for ACTIVE screen status…")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                }
            }
            
            if tvConfigReady, !networkMonitor.isConnected, !isReady, hasSecureKey, !showActivation {
                ConnectionLostView()
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .initialHeartbeatSucceeded)) { _ in
            isReady = true
            showActivation = false
            status = "Screen ACTIVE"
        }
        .onReceive(NotificationCenter.default.publisher(for: .initialHeartbeatFailed)) { _ in
            status = "Screen not ACTIVE. Redirecting to registration…"
            isReady = false
            showActivation = true
        }
        .onChange(of: networkMonitor.isConnected) { connected in
            if connected && !isReady && hasSecureKey && !showActivation {
                status = "Connection restored. Retrying heartbeat…"
                HeartbeatAPI.shared.resetInitialHeartbeatGate()
                HeartbeatAPI.shared.startInitialHeartbeat()
            }
        }
        .task {
            await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
            tvConfigReady = true
            if !AppRootViewModel.hasSavedSecureKey() {
                showActivation = true
                status = "Registration required"
            } else {
                status = "Sending heartbeat…"
                HeartbeatAPI.shared.startInitialHeartbeat()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !isReady {
                NetworkMonitor.shared.refreshConnectivity()
            }
        }
    }
}
