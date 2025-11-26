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
    private var pendingGroups: [AdSequenceGroup] = []
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
    private var repeatInTime: Double = 3 * 60
    private var lastAppliedSync: Date = .distantPast


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
            self.startAutoSync(screenId: self.screenId)
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
//            if ad.isTooLarge {
//                print("⏭️ Skipping large asset (\(ad.itemsize ?? "unknown")) — \(ad.itemurl)")
//                completed += 1
//                await MainActor.run { preloadProgress = completed / total }
//                continue
//            }

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
        let fileName = remoteURL.lastPathComponent.lowercased()
        let destination = adsCacheDir.appendingPathComponent(fileName)

        // If cached already → return
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        do {
            print("⬇️ Downloading:", fileName)
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: destination)
            print("💾 Saved:", fileName)

            // ⭐ ADD THIS BLOCK — decode & cache image immediately ⭐
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") {
                if let img = UIImage(data: data) {
                    await MainActor.run {
                        self.imageCache[remoteURLString] = img
                    }
                    print("🖼️ Cached image during download:", fileName)
                }
            }
            // ⭐ END ⭐

            return destination

        } catch {
            print("❌ Failed to download \(fileName): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func preloadPendingGroups() async {
        guard !pendingGroups.isEmpty else { return }

        print("⏳ Preloading NEW playlist assets…")

        let allPendingAds = pendingGroups.flatMap { $0.ii }
        for ad in allPendingAds {
            if let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
        }

        print("✅ Finished preloading NEW playlist")
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

        let ads = group.ii
        // 1. Try video first ONLY if it's first in list
            if let first = ads.first {
                if first.assettype.lowercased() == "video" {
                    playVideo(first)
                    return
                }
            }

            // 2. If no leading video → show images for group duration
            startGroupTimer()

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
                print("🔁 Loop finished.")

                let now = Date()
                if now.timeIntervalSince(self.lastAppliedSync) >= self.repeatInTime {
                    if !self.pendingGroups.isEmpty {
                        print("📥 Time to apply new playlist — preparing safely…")
                        Task {
                            await self.applyPendingPlaylistSafely()
                        }
                        return
                    }
                }
                
                // Normal reset
                self.currentIndex = 0
                self.playCurrentGroup()
            }

            self.slideOffset = 0
            self.playCurrentGroup()
        }
    }
    
    // MARK: - Safely apply new synced playlist
    private func applyPendingPlaylistSafely() async {
        print("📥 Applying NEW playlist safely…")

        // STEP 1: Reset old data
        self.localURLs.removeAll()
        self.imageCache.removeAll()

        // STEP 2: Copy preloaded pending URLs into localURLs
        for group in pendingGroups {
            for ad in group.ii {
                if let fileURL = adsCacheDir.appendingPathComponent(URL(string: ad.itemurl)!.lastPathComponent)
                    .absoluteURL as URL?,
                   fileManager.fileExists(atPath: fileURL.path)
                {
                    self.localURLs[ad.itemurl] = fileURL
                }
            }
        }

        // STEP 3: Replace playlist
        self.groupedAds = self.pendingGroups
        self.pendingGroups.removeAll()
        self.currentIndex = 0
        self.lastAppliedSync = Date()

        // STEP 4: Decode ALL images fully before playback
        print("🖼️ Rebuilding imageCache from disk…")

        for (key, url) in localURLs {
            if ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                if let data = try? Data(contentsOf: url),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        self.imageCache[key] = img
                    }
                }
            }
        }

        print("🎉 New playlist ready — starting playback\n")

        await MainActor.run {
            self.playCurrentGroup()
        }
    }

    // MARK: - Auto Sync
    func startAutoSync(screenId: String) {
//        syncAds(with: screenId)
        syncTimer = Timer.scheduledTimer(withTimeInterval: repeatInTime, repeats: true) { [weak self] _ in
            self?.syncAds(with: screenId)
        }
    }

    private func syncAds(with screenId: String) {
        reqNum = reqNum + 1
        print("🌐 Running periodic API sync... with reqNum: \(reqNum)")
        APIService.shared.fetchItemSeqInfo(screenId: screenId, reqNum: reqNum) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("🔄 Sync data fetched: \(response.groupedAds.count) groups")

                    // Store in pending (but DO NOT apply yet)
                    self.pendingGroups = response.groupedAds

                    // ⭐ PRELOAD NEW PLAYLIST IMMEDIATELY ⭐
                    Task {
                        await self.preloadPendingGroups()
                    }
                    
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
