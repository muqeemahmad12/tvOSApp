//
//  AdPlayerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI
import AVKit

// MARK: - Player View
struct AdPlayerView: View {
    @StateObject private var playerVM = AdPlayerViewModelNew()
    @ObservedObject var listVM: AdListViewModel

    var body: some View {
        ZStack {
            if playerVM.isPreloading {
                VStack {
                    ProgressView(value: playerVM.preloadProgress) {
                        Text("Preloading assets...")
                    }
                    .padding()
                }
            } else if let ad = playerVM.currentAd {
                Group {
                    if ad.assettype.lowercased() == "video" {
                        if let player = playerVM.player {
                            VideoPlayer(player: player)
                                .opacity(playerVM.transitionOpacity)
                                .transition(.opacity)
                        }
                    } else {
                        if let url = playerVM.localURL(for: ad) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .opacity(playerVM.transitionOpacity)
                            .transition(.opacity)
                        }
                    }
                }
                .id(ad.itemid)
            } else {
                Text("🎬 Ready for playback")
                    .foregroundColor(.gray)
            }
        }
        .onChange(of: listVM.ads) { newAds in
            if !newAds.isEmpty {
                playerVM.startPlayback(with: newAds)
            }
        }
        .onAppear {
            if !listVM.ads.isEmpty {
                playerVM.startPlayback(with: listVM.ads)
            }
        }
        .onDisappear {
            playerVM.stop()
        }
    }
}
