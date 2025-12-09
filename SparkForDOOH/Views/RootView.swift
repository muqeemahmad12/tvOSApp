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

    var body: some View {
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
    }
}


