//
//  AdPlayerView.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI
import AVKit
import UIKit

struct AdPlayerView: View {
    @StateObject private var viewModel = AdPlayerViewModel()
    @ObservedObject var listVM: AdPlaylistViewModel
    @State private var videoFullScreen = false
    @State private var tickerMessage: String? = nil
    @State private var logoUrl: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isPreloading {
                PlayerLoadingPlaceholderView()
            } else if let group = viewModel.currentGroup {
                GeometryReader { geo in
                    let videos = group.ii.filter { $0.assettype.lowercased() == "video" }
                    let images = group.ii.filter { $0.assettype.lowercased() == "image" }
                
                    let hasVideo = !videos.isEmpty
                    let hasImages = !images.isEmpty
                    
                    let screenWidth = geo.size.width
                    let screenHeight = geo.size.height
                    let videoWidth = hasImages ? screenWidth * 0.7 : screenWidth
                    let videoHeight = hasImages ? videoWidth * 9 / 16 : screenHeight
                    let bottomImageHeight = screenHeight - videoHeight
                    let rightImageWidth = screenWidth - videoWidth
                    
                    if hasImages && !hasVideo && images.count == 1 {
                        if let img = viewModel.imageCache[images[0].itemurl] {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        ZStack(alignment: .topLeading) {
                            // MARK: - Video Player
                            if let _ = group.ii.first(where: { $0.assettype.lowercased() == "video" }) {
                                VideoPlayer(player: viewModel.activePlayer)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()
                                    .position(x: videoWidth / 2,
                                              y: hasImages ? (videoHeight / 2) : screenHeight / 2)
                                    .animation(.easeInOut(duration: 1.0), value: hasImages)
                            }
                            
                            // MARK: - Bottom Image
                            if let bottomAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).first {
                                if let img = viewModel.imageCache[bottomAd.itemurl] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: videoWidth, height: bottomImageHeight)
                                        .clipped()
                                        .position(x: videoWidth / 2,
                                                  y: screenHeight - bottomImageHeight / 2)
                                }
                            }
                            
                            // MARK: - Right Vertical Image (20% width)
                            if let rightAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).last {
                                if let img = viewModel.imageCache[rightAd.itemurl] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: (screenWidth - videoWidth),
                                               height: screenHeight)
                                        .clipped()
                                        .position(x: videoWidth + (rightImageWidth / 2),
                                                  y: screenHeight / 2)
                                }
                            }
                        }
                    }
                }
            } else {
                PlayerLoadingPlaceholderView()
            }
            
            // MARK: - Ticker/Banner Overlay (with time display)
            if !viewModel.isPreloading {
                TickerBannerView(
                    tickerMessage: tickerMessage,
                    logoUrl: logoUrl,
                    showTime: true  // Can be controlled via config
                )
            }
        }
        .ignoresSafeArea() // Ensure the entire player fills the tvOS window
        .accessibilityIdentifier("AdPlayerRootView")
        // MARK: - ViewModel Triggers
        .onChange(of: listVM.groupedAds) { newGroups in
            if !newGroups.isEmpty {
                viewModel.startPlayback(with: newGroups)
            }
        }
        .onAppear {
            // Prevent screensaver/sleep while playing ads
            UIApplication.shared.isIdleTimerDisabled = true
            print("🔒 Idle timer disabled - preventing screensaver")
            
            // Configure media session (suppress Now Playing, handle remote)
            MediaSessionHelper.shared.setupForDOOHPlayback()
            
            // Load ticker/logo from saved activation data
            tickerMessage = AppRootViewModel.getSavedTickerMessage()
            logoUrl = AppRootViewModel.getSavedLogoUrl()
            
            // Start heartbeat service
            HeartbeatAPI.shared.startHeartbeat()
            
            if !listVM.groupedAds.isEmpty {
                viewModel.startPlayback(with: listVM.groupedAds)
            }
        }
        .onDisappear {
            // Re-enable idle timer when leaving player
            UIApplication.shared.isIdleTimerDisabled = false
            print("🔓 Idle timer re-enabled")
            
            // Cleanup media session
            MediaSessionHelper.shared.cleanup()
            
            viewModel.stop()
            HeartbeatAPI.shared.stopHeartbeat()
        }
        // Listen for ticker/logo updates from heartbeat
        .onReceive(NotificationCenter.default.publisher(for: .tickerUpdated)) { _ in
            tickerMessage = AppRootViewModel.getSavedTickerMessage()
            logoUrl = AppRootViewModel.getSavedLogoUrl()
        }
    }
}

/// Shared loading/placeholder layout used while ads are preloading or when there is no data yet.
private struct PlayerLoadingPlaceholderView: View {
    var body: some View {
        ZStack {
            FullscreenBackground(imageName: "placeholder_image")

            VStack {
                Text("Loading Informational Sparks \n for your clinical display")
                    .font(.system(size: 90))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#138bcc"))
                    .padding(.top, 50)

                Text("Your display will start automatically once the initial download is complete.")
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#505050"))

                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image("tv_frame")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 1050)
                        .padding(.trailing, 35)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

