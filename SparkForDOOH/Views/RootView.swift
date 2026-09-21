//
//  RootView.swift
//  SparkForDOOH
//
//  Created by Cursor on 03/12/25.
//

import SwiftUI

/// Top-level view that decides whether to show activation or the ad player.
struct RootView: View {
    @StateObject private var appVM = AppRootViewModel()
    @StateObject private var adListVM = AdPlaylistViewModel()
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                switch appVM.phase {
                case .activating:
                    ActivationView {
                        adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
                        appVM.phase = .playing
                    }
                    .id(appVM.activationSessionID)
                case .playing:
                    AdPlayerView(listVM: adListVM)
                }
            }

            // INACTIVE: Screen Inactivated — stay until heartbeat returns ACTIVE (cache kept).
            if appVM.isScreenInactivated {
                ScreenInactivatedView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            // DELETED: Screen Deactivated — credentials cleared; re-register after restart.
            if appVM.isScreenDeactivated {
                ScreenDeactivatedView()
                    .transition(.opacity)
                    .zIndex(11)
            }
            
            // Offline with no playlist at all (player not yet preloading).
            // Preload / loading-with-no-playable-content is handled inside AdPlayerView.
            if !networkMonitor.isConnected
                && !appVM.isScreenDeactivated
                && !appVM.isScreenInactivated
                && appVM.phase == .playing
                && adListVM.groupedAds.isEmpty {
                ConnectionLostView()
                    .transition(.opacity)
                    .zIndex(20)
            }

            // Show waiting screen when online but no playlist/content is assigned yet.
            if appVM.phase == .playing,
               !appVM.isScreenDeactivated,
               !appVM.isScreenInactivated,
               networkMonitor.isConnected,
               adListVM.groupedAds.isEmpty,
               adListVM.isLoading == false,
               adListVM.isUsingCachedPlaylist == false {
                WaitingForContentView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            if HeartbeatAPI.shared.isAwaitingActiveStatus {
                appVM.handleScreenInactivation()
            }
            if appVM.phase == .playing, !appVM.isScreenDeactivated, !appVM.isScreenInactivated {
                SentryService.shared.track(
                    SentryAnalyticsEvent.screenPlayingPhase,
                    attributes: ["screen_id": AppConfig.current.screenId]
                )
                adListVM.loadCachedPlaylistIfAvailable()
                if networkMonitor.isConnected {
                    adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
                } else if !adListVM.groupedAds.isEmpty {
                    print("📴 Offline restart — playing from cache; quest deferred until online")
                } else {
                    print("📴 Offline restart — no cache; waiting for connectivity")
                }
            }
        }
        .onChange(of: appVM.phase) { phase in
            if phase == .playing {
                SentryService.shared.track(
                    SentryAnalyticsEvent.screenPlayingPhase,
                    attributes: ["screen_id": AppConfig.current.screenId]
                )
                SentryService.shared.breadcrumb(category: "lifecycle", message: "playing_phase", data: [:])
            }
        }
        .onChange(of: networkMonitor.isConnected) { isConnected in
            guard isConnected else { return }
            print("🌐 Network restored — resuming APIs immediately")
            switch appVM.phase {
            case .playing:
                if !appVM.isScreenDeactivated && !appVM.isScreenInactivated {
                    HeartbeatAPI.shared.startHeartbeat()
                    HeartbeatAPI.shared.kickHeartbeatNow()
                    adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
                } else if appVM.isScreenInactivated {
                    HeartbeatAPI.shared.startHeartbeat()
                    HeartbeatAPI.shared.kickHeartbeatNow()
                }
            case .activating:
                HeartbeatAPI.shared.resetInitialHeartbeatGate()
                HeartbeatAPI.shared.startInitialHeartbeat()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, !networkMonitor.isConnected {
                NetworkMonitor.shared.refreshConnectivity()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidInactivate)) { _ in
            appVM.handleScreenInactivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidDeactivate)) { _ in
            appVM.handleScreenDeactivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .heartbeatScreenStatusActive)) { _ in
            // Only fired when recovering from inactivation (see HeartbeatAPI).
            appVM.handleScreenReactivation()
            print("📥 Re-activated — resume playlist + one quest fetch")
            adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
        }
    }
}
