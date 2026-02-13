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
                        // When activation completes, start fetching ads and switch to player
                        adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
                        appVM.phase = .playing
                    }
                case .playing:
                    AdPlayerView(listVM: adListVM)
                }
            }
            
            // Show offline overlay only during activation when we truly have no content.
            if appVM.phase == .activating && !networkMonitor.isConnected && adListVM.groupedAds.isEmpty {
                ConnectionLostView()
                    .transition(.opacity)
            }

            // Show waiting screen when online but no playlist/content is assigned yet.
            if appVM.phase == .playing,
               networkMonitor.isConnected,
               adListVM.groupedAds.isEmpty,
               adListVM.isLoading == false,
               adListVM.isUsingCachedPlaylist == false {
                WaitingForContentView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            // If already activated (from previous launch), load cached playlist first for fast start
            if appVM.phase == .playing {
                // Load cached playlist immediately for instant playback
                adListVM.loadCachedPlaylistIfAvailable()
                
                // Then fetch fresh data from API (will update if different)
                adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
            }
        }
        .onChange(of: networkMonitor.isConnected) { isConnected in
            guard isConnected else { return }
            // When connectivity returns, resume normal flow:
            // - If already playing, refresh playlist to ensure up-to-date content.
            // - If still gating activation, kick the initial heartbeat again (it self-retries).
            switch appVM.phase {
            case .playing:
                adListVM.fetchAds(screenId: AppConfig.current.screenId, reqNum: 1)
            case .activating:
                HeartbeatAPI.shared.startInitialHeartbeat()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active, !networkMonitor.isConnected {
                NetworkMonitor.shared.refreshConnectivity()
            }
        }
    }
}


