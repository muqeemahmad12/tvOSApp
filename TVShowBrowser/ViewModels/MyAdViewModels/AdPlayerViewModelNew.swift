//
//  AdPlayerViewModelNew.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import AVKit
import SwiftUI

@MainActor
final class AdPlayerViewModelNew: ObservableObject {
    // MARK: - Published
    @Published var currentGroup: AdSequenceGroup?
    @Published var nextGroup: AdSequenceGroup?
    @Published var groupedAds: [AdSequenceGroup] = []
    @Published var imageCache: [String: UIImage] = [:]
    @Published var slideOffset: CGFloat = 0.0
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0.0
    @Published var errorMessage: String?

    // MARK: - Private
    private var currentIndex = 0
    var activePlayer: AVPlayer?
    private var timer: Timer?
    private var syncTimer: Timer?
    private var reqNum = 1
    private var screenId = "174"

    // MARK: - Public entry point
    func startPlayback(with groups: [AdSequenceGroup]) {
        guard !groups.isEmpty else {
            print("⚠️ No groups to play.")
            return
        }
        groupedAds = groups
        currentIndex = 0
        playCurrentGroup()
        startAutoSync(screenId: screenId)
    }

    // MARK: - Play a full group (1 video + 2 images)
    private func playCurrentGroup() {
        guard currentIndex < groupedAds.count else { return }
        let group = groupedAds[currentIndex]
        currentGroup = group
        print("▶️ Playing group \(group.sequence) — \(group.ii.count) ads")

        // Prepare video player (expect 1 video per group)
        if let videoAd = group.ii.first(where: { $0.assettype.lowercased() == "video" }),
           let videoURL = URL(string: videoAd.itemurl) {
            activePlayer = AVPlayer(url: videoURL)
            activePlayer?.play()

            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: activePlayer?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.transitionToNextGroup()
            }
        } else {
            // No video -> fallback timer
            startGroupTimer()
        }

        // Preload images
        Task {
            for ad in group.ii where ad.assettype.lowercased() == "image" {
                await self.loadImage(for: ad)
            }
        }
    }

    // MARK: - Load image async
    private func loadImage(for ad: AdItemModel) async {
        guard imageCache[ad.itemurl] == nil,
              let url = URL(string: ad.itemurl) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                imageCache[ad.itemurl] = image
                print("🖼️ Cached image:", ad.itemurl)
            }
        } catch {
            print("❌ Failed to load image:", error)
        }
    }

    // MARK: - Fallback timer if no video
    private func startGroupTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            self?.transitionToNextGroup()
        }
    }

    // MARK: - Transition
    private func transitionToNextGroup() {
        withAnimation(.easeInOut(duration: 0.8)) {
            slideOffset = -UIScreen.main.bounds.width
        }

        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height

        print("Screen size: \(screenWidth)x\(screenHeight)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.currentIndex += 1
            if self.currentIndex >= self.groupedAds.count {
                print("✅ All groups played, restarting.")
                self.currentIndex = 0
            }
            self.slideOffset = 0
            self.playCurrentGroup()
        }
    }

    // MARK: - Auto Sync (unchanged)
    func startAutoSync(screenId: String) {
        syncAds(with: screenId)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3 * 60, repeats: true) { [weak self] _ in
            self?.syncAds(with: screenId)
        }
    }

    private func syncAds(with screenId: String) {
        print("🌐 Running periodic API sync...")
        reqNum += 1
        APIService.shared.fetchItemSeqInfo(screenId: screenId, reqNum: reqNum) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let groups = response.groupedAds
                    self.groupedAds = groups
                    print("✅ Synced \(groups.count) groups.")
                case .failure(let error):
                    print("❌ Sync failed:", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Stop
    func stop() {
        activePlayer?.pause()
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        syncTimer?.invalidate()
    }
}
