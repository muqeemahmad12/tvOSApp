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
                    let mainIdx = group.lShapeMainIndex
                    let mainItem = mainIdx.map { group.ii[$0] }
                    let companions = group.lShapeCompanions
                    let playableMainVideo = mainItem.map { $0.isVideoType && $0.hasMinimumPlayableFields } ?? false
                    let unplayableMainVideo = mainItem.map { $0.isVideoType && !$0.hasMinimumPlayableFields } ?? false
                    let hasCompanionSlots = !companions.isEmpty
                    let showLShape = viewModel.showsLShapeCompanions
                    let showWhiteMain = viewModel.showWhiteMainSlot
                    let showMainLoader = viewModel.isMainSlotLoading

                    // Video (or white/loader main slot) + companions while L-shape is active.
                    let showVideoCompanions = (playableMainVideo || unplayableMainVideo || showWhiteMain || showMainLoader)
                        && hasCompanionSlots && showLShape
                    // Image-only layouts (no video slot in group) — collapse when showLShape is false.
                    let imageOnlyPair = mainIdx == nil && companions.count == 2 && showLShape
                    let imageOnlyMulti = mainIdx == nil && companions.count >= 3 && showLShape
                    let imageOnlyFullscreen = mainIdx == nil && !companions.isEmpty && !showLShape

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

                    // Slot mapping by API order — never reuse one companion for two slots when
                    // another (possibly unplayable) item exists for that place.
                    let mainImage: AdItemModel? = (imageOnlyPair || imageOnlyMulti || imageOnlyFullscreen) ? companions[0] : nil
                    let bottomImage: AdItemModel? = {
                        if showVideoCompanions { return companions[0] }
                        if imageOnlyMulti { return companions[1] }
                        return nil
                    }()
                    let rightImage: AdItemModel? = {
                        if showVideoCompanions {
                            if companions.count >= 2 { return companions[1] }
                            // True single companion (video + 1 item only) → both side panels.
                            return group.ii.count == 2 ? companions[0] : nil
                        }
                        if imageOnlyPair || imageOnlyMulti { return companions.last }
                        return nil
                    }()

                    if mainIdx == nil && companions.count == 1 {
                        if showMainLoader {
                            mainSlotLoader(width: geo.size.width, height: geo.size.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        } else if showWhiteMain {
                            Color.white
                                .frame(width: geo.size.width, height: geo.size.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        } else {
                            slotContent(for: companions[0], width: geo.size.width, height: geo.size.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    } else {
                        ZStack(alignment: .topLeading) {
                            // MARK: - Main (loader / white / video / lead image)
                            if showMainLoader {
                                mainSlotLoader(width: videoWidth, height: videoHeight)
                                    .position(
                                        x: videoWidth / 2,
                                        y: showVideoCompanions ? (videoHeight / 2) : screenHeight / 2
                                    )
                                    .animation(
                                        viewModel.animateLShapeLayoutChange ? .easeInOut(duration: 1.0) : nil,
                                        value: showVideoCompanions
                                    )
                            } else if showWhiteMain {
                                Color.white
                                    .frame(width: videoWidth, height: videoHeight)
                                    .position(
                                        x: videoWidth / 2,
                                        y: showVideoCompanions ? (videoHeight / 2) : screenHeight / 2
                                    )
                                    .animation(
                                        viewModel.animateLShapeLayoutChange ? .easeInOut(duration: 1.0) : nil,
                                        value: showVideoCompanions
                                    )
                            } else if playableMainVideo {
                                // Non-interactive layer so Menu reaches the exit confirmation
                                // (SwiftUI VideoPlayer steals focus and swallows Menu).
                                NonInteractiveVideoPlayer(player: viewModel.activePlayer)
                                    .aspectRatio(16/9, contentMode: showVideoCompanions ? .fit : .fill)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()
                                    .allowsHitTesting(false)
                                    .position(x: videoWidth / 2,
                                              y: showVideoCompanions ? (videoHeight / 2) : screenHeight / 2)
                                    .animation(
                                        viewModel.animateLShapeLayoutChange ? .easeInOut(duration: 1.0) : nil,
                                        value: showVideoCompanions
                                    )
                            } else if let mainImage {
                                slotContent(for: mainImage, width: videoWidth, height: videoHeight)
                                    .position(x: videoWidth / 2, y: showVideoCompanions || imageOnlyMulti ? (videoHeight / 2) : screenHeight / 2)
                            }

                            // MARK: - Bottom Image
                            if let bottomImage, bottomImageHeight > 1 {
                                slotContent(for: bottomImage, width: videoWidth, height: bottomImageHeight)
                                    .position(x: videoWidth / 2,
                                              y: screenHeight - bottomImageHeight / 2)
                            }

                            // MARK: - Right Vertical Image
                            if let rightImage {
                                slotContent(for: rightImage, width: rightImageWidth, height: screenHeight)
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
                    LoadingView(downloadProgress: viewModel.isPreloading ? viewModel.preloadProgress : nil)
                }
            }
            
            // MARK: - Ticker/Banner Overlay (with time display)
            // Keep above main-slot loader/video so buffering never covers or remount-stops the marquee.
            if viewModel.isPlayerReadyForOverlay {
                TickerBannerView(
                    tickerMessage: tickerMessage,
                    logoUrl: logoUrl,
                    showTime: true  // Can be controlled via config
                )
                .zIndex(10)
                .allowsHitTesting(false)
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
            if HeartbeatAPI.shared.isAwaitingActiveStatus {
                viewModel.pauseForDeactivation()
            }
        }
        .onDisappear {
            // Re-enable idle timer when leaving player
            UIApplication.shared.isIdleTimerDisabled = false
            print("🔓 Idle timer re-enabled")
            
            // Cleanup media session
            MediaSessionHelper.shared.cleanup()
            
            viewModel.stop()
            TickerMarqueeEngine.shared.stop()
            // Keep heartbeat while deactivated so we can wait for ACTIVE.
            if !HeartbeatAPI.shared.isAwaitingActiveStatus {
                HeartbeatAPI.shared.stopHeartbeat()
            }
        }
        // Listen for ticker/logo updates from heartbeat — refresh overlay immediately.
        .onReceive(NotificationCenter.default.publisher(for: .tickerUpdated)) { _ in
            tickerMessage = AppRootViewModel.getSavedTickerMessage()
            logoUrl = AppRootViewModel.getSavedLogoUrl()
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidDeactivate)) { _ in
            viewModel.pauseForDeactivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidInactivate)) { _ in
            viewModel.pauseForDeactivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .heartbeatScreenStatusActive)) { _ in
            // Notification is only posted when recovering from deactivation (see HeartbeatAPI).
            viewModel.resumeAfterReactivation()
        }
        // Auto-resume playback when app becomes active (TV wake, resume from background)
        .onChange(of: scenePhase) { phase in
            if phase == .active, !HeartbeatAPI.shared.isAwaitingActiveStatus {
                viewModel.resumePlayback()
            }
        }
    }
    
    // MARK: - Main slot buffering (avoids blank white while media prepares)
    private func mainSlotLoader(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(2.0)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Slot helpers (playable image or white placeholder)
    @ViewBuilder
    private func slotContent(for ad: AdItemModel, width: CGFloat, height: CGFloat) -> some View {
        if ad.hasMinimumPlayableFields, let img = resolveImage(for: ad) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } else {
            Color.white
                .frame(width: width, height: height)
        }
    }

    // MARK: - Helper to resolve images (cache, bundle, or safe content)
    private func resolveImage(for ad: AdItemModel) -> UIImage? {
        // Check if it's a bundle image (safe content)
        if ad.itemurl.hasPrefix("bundle://") {
            let imageName = ad.itemurl.replacingOccurrences(of: "bundle://", with: "")
            return UIImage(named: imageName) ?? UIImage(named: "placeholder_image")
        }
        
        // Otherwise look in the cache
        return viewModel.imageCache[ad.itemurl]
    }
}
