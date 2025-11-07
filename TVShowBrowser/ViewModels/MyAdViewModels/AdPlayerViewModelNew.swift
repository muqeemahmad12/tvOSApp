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

    // MARK: - File Manager helpers
    private var fileManager: FileManager { .default }
    private var adsCacheDir: URL {
        let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("AdsCache")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    private var localURLs: [String: URL] = [:]

    // MARK: - Entry point
    func startPlayback(with groups: [AdSequenceGroup]) {
        guard !groups.isEmpty else {
            print("⚠️ No groups to play.")
            return
        }
        groupedAds = groups
        currentIndex = 0
        Task {
            await preloadAllAssets()
            playCurrentGroup()
            startAutoSync(screenId: screenId)
        }
    }

    // MARK: - Preload all assets before playback
    private func preloadAllAssets() async {
        isPreloading = true
        preloadProgress = 0.0
        localURLs.removeAll()

        // Flatten all ads in all groups
        let allAds = groupedAds.flatMap { $0.ii }
        let total = Double(allAds.count)
        var completed = 0.0

        for ad in allAds {
            if ad.isTooLarge {
                print("⏭️ Skipping large asset (\(ad.itemsize ?? "unknown")) — \(ad.itemurl)")
                completed += 1
                await MainActor.run { preloadProgress = completed / total }
                continue
            }

            if let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
            completed += 1
            await MainActor.run { preloadProgress = completed / total }
        }

        await MainActor.run {
            isPreloading = false
            print("✅ All assets downloaded to \(adsCacheDir.lastPathComponent)")
            checkFileManager()
        }
    }

    // MARK: - Download one asset
    private func downloadAsset(_ remoteURLString: String) async -> URL? {
        guard let remoteURL = URL(string: remoteURLString) else { return nil }
        let fileName = remoteURL.lastPathComponent
        let destination = adsCacheDir.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destination.path) {
            return destination // use cached
        }

        do {
            print("⬇️ Downloading:", fileName)
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: destination)
            print("💾 Saved:", fileName)
            return destination
        } catch {
            print("❌ Failed to download \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Debug info
    private func checkFileManager() {
        if let files = try? fileManager.contentsOfDirectory(at: adsCacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            var total: UInt64 = 0
            for file in files {
                let size = (try? fileManager.attributesOfItem(atPath: file.path)[.size] as? UInt64) ?? 0
                total += size ?? 0
                let mb = Double(size ?? 0) / (1024 * 1024)
                print("📄 \(file.lastPathComponent) — \(String(format: "%.2f MB", mb))")
            }
            print("📦 Total cache: \(String(format: "%.2f MB", Double(total) / (1024 * 1024)))\n")
        }
    }

    // MARK: - Play current group (from local cache)
    private func playCurrentGroup() {
        guard currentIndex < groupedAds.count else { return }
        let group = groupedAds[currentIndex]
        currentGroup = group
        print("▶️ Playing group \(group.sequence) — \(group.ii.count) ads")

        // Video first (if present)
        if let videoAd = group.ii.first(where: { $0.assettype.lowercased() == "video" }) {
            playVideo(videoAd)
        } else {
            startGroupTimer()
        }

        // Preload images into memory
        Task {
            for ad in group.ii where ad.assettype.lowercased() == "image" {
                await self.loadImage(for: ad)
            }
        }
    }

    private func playVideo(_ ad: AdItemModel) {
        let localURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl)!
        activePlayer = AVPlayer(url: localURL)
        activePlayer?.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: activePlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.transitionToNextGroup()
        }
    }

    // MARK: - Image loading (from local)
    private func loadImage(for ad: AdItemModel) async {
        if imageCache[ad.itemurl] != nil { return }

        let localURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl)!
        do {
            let data = try Data(contentsOf: localURL)
            if let image = UIImage(data: data) {
                await MainActor.run { imageCache[ad.itemurl] = image }
                print("🖼️ Cached image:", ad.itemurl)
            }
        } catch {
            print("❌ Image load failed:", error)
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

    // MARK: - Auto Sync
    func startAutoSync(screenId: String) {
        syncAds(with: screenId)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
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
                    self.groupedAds = response.groupedAds
                    print("✅ Synced \(response.groupedAds.count) groups.")
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
