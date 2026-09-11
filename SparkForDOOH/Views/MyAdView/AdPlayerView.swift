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
    @Environment(\.scenePhase) private var scenePhase
    @State private var videoFullScreen = false
    @State private var tickerMessage: String? = nil
    @State private var logoUrl: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isWaitingForPlayableContent {
                WaitingForContentView()
            } else if viewModel.isPreloading {
                LoadingView(downloadProgress: viewModel.preloadProgress)
            } else if let group = viewModel.currentGroup {
                GeometryReader { geo in
                    let videos = group.ii.filter { $0.assettype.lowercased() == "video" }
                    let images = group.ii.filter { $0.assettype.lowercased() == "image" }

                    let hasVideo = !videos.isEmpty
                    let hasImages = !images.isEmpty
                    // Video + companions while L-shape is active; then video scales fullscreen.
                    let showVideoCompanions = hasVideo && hasImages && viewModel.showsLShapeCompanions
                    // 2 images, no video → fill left column full-height; 3+ use video+bottom+right slots with images.
                    let imageOnlyPair = !hasVideo && images.count == 2
                    let imageOnlyMulti = !hasVideo && images.count >= 3

                    let screenWidth = geo.size.width
                    let screenHeight = geo.size.height
                    let videoWidth = (showVideoCompanions || imageOnlyPair || imageOnlyMulti) ? screenWidth * 0.7 : screenWidth
                    let videoHeight: CGFloat = {
                        if imageOnlyPair { return screenHeight }
                        if showVideoCompanions || imageOnlyMulti { return videoWidth * 9 / 16 }
                        return screenHeight
                    }()
                    let bottomImageHeight = screenHeight - videoHeight
                    let rightImageWidth = screenWidth - videoWidth

                    // Slot mapping when API sends images in the "video" position:
                    // main  = video OR images[0] (image-only multi)
                    // bottom = first image with video; images[1] when 3+ images only
                    // right  = last image when 2+ images
                    let mainImage: AdItemModel? = (imageOnlyPair || imageOnlyMulti) ? images[0] : nil
                    let bottomImage: AdItemModel? = {
                        if showVideoCompanions { return images.first }
                        if imageOnlyMulti { return images[1] }
                        return nil
                    }()
                    let rightImage: AdItemModel? = {
                        if showVideoCompanions, images.count >= 1 { return images.last }
                        if !hasVideo, images.count >= 2 { return images.last }
                        return nil
                    }()

                    if hasImages && !hasVideo && images.count == 1 {
                        if let img = resolveImage(for: images[0]) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        ZStack(alignment: .topLeading) {
                            // MARK: - Main (video fullscreen or L-shape, or lead image when no video)
                            if hasVideo {
                                // Non-interactive layer so Menu reaches the exit confirmation
                                // (SwiftUI VideoPlayer steals focus and swallows Menu).
                                NonInteractiveVideoPlayer(player: viewModel.activePlayer)
                                    .aspectRatio(16/9, contentMode: showVideoCompanions ? .fit : .fill)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()
                                    .allowsHitTesting(false)
                                    .position(x: videoWidth / 2,
                                              y: showVideoCompanions ? (videoHeight / 2) : screenHeight / 2)
                                    .animation(.easeInOut(duration: 1.0), value: showVideoCompanions)
                            } else if let mainImage, let img = resolveImage(for: mainImage) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()
                                    .position(x: videoWidth / 2,
                                              y: videoHeight / 2)
                            }

                            // MARK: - Bottom Image
                            if let bottomImage, bottomImageHeight > 1, let img = resolveImage(for: bottomImage) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: videoWidth, height: bottomImageHeight)
                                    .clipped()
                                    .position(x: videoWidth / 2,
                                              y: screenHeight - bottomImageHeight / 2)
                            }

                            // MARK: - Right Vertical Image
                            if let rightImage, let img = resolveImage(for: rightImage) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: rightImageWidth, height: screenHeight)
                                    .clipped()
                                    .position(x: videoWidth + (rightImageWidth / 2),
                                              y: screenHeight / 2)
                            }
                        }
                    }
                }
            } else {
                // No current group yet — prefer waiting over perpetual black/loading when playlist is empty.
                if listVM.groupedAds.isEmpty && !listVM.isLoading {
                    WaitingForContentView()
                } else {
                    LoadingView()
                }
            }
            
            // MARK: - Ticker/Banner Overlay (with time display)
            if viewModel.isPlayerReadyForOverlay {
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
            viewModel.startPlayback(with: newGroups)
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
            
            viewModel.startPlayback(with: listVM.groupedAds)
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
        // Auto-resume playback when app becomes active (TV wake, resume from background)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                viewModel.resumePlayback()
            }
        }
    }
    
    // MARK: - Helper to resolve images (cache, bundle, or safe content)
    private func resolveImage(for ad: AdItemModel) -> UIImage? {
        // Check if it's a bundle image (safe content)
        if ad.itemurl.hasPrefix("bundle://") {
            let imageName = ad.itemurl.replacingOccurrences(of: "bundle://", with: "")
            return UIImage(named: imageName) ?? SafeContentManager.shared.getSafeContentImage()
        }
        
        // Otherwise look in the cache
        return viewModel.imageCache[ad.itemurl]
    }
}
