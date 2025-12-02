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
    private var repeatInTime: Double = 5 * 60
    private var lastAppliedSync: Date = .distantPast


    // MARK: - File Manager helpers
    private var fileManager: FileManager { .default }
    private var adsCacheDir: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("AdsCache")
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
//        groupedAds = groups
        currentIndex = 0
        Task {
            groupedAds = await filterUnplayableAds(newAds: groups)        // <-- new: remove bad videos before playback
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
    
    // MARK: - NEW: Remove unplayable video items & empty groups
    private func filterUnplayableAds(newAds: [AdSequenceGroup]) async -> [AdSequenceGroup] {
            print("🔎 Validating playable videos before starting playback…")
            var newGroups: [AdSequenceGroup] = []

            for group in newAds {
                var keptAds: [AdItemModel] = []
                for ad in group.ii {
                    // images always kept (we assume)
                    if ad.assettype.lowercased() != "video" {
                        keptAds.append(ad)
                        continue
                    }

                    // for video, require a local URL or remote URL
                    guard let candidateURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl) else {
                        print("❌ Removing (invalid URL):", ad.itemurl)
                        continue
                    }

                    let playable = await isVideoPlayable(url: candidateURL)
                    if playable {
                        keptAds.append(ad)
                    } else {
                        print("❌ Removing unplayable video:", ad.itemurl)
                    }
                }

                if !keptAds.isEmpty {
                    var g = group
                    g.ii = keptAds
                    newGroups.append(g)
                } else {
                    print("⚠️ Removing entire group \(group.sequence) because it has no playable items")
                }
            }

            // apply filtered groups
            return newGroups
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
        guard let localURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl) else {
            print("Invalid URL:", ad.itemurl)
            transitionToNextItem()
            return
        }

        activePlayer = AVPlayer(url: localURL)
        activePlayer?.play()
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: activePlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.transitionToNextItem()
            }
        }
    }
    
    func isVideoPlayable(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)

        do {
            // Load "isPlayable" property asynchronously
            let playable = try await asset.load(.isPlayable)
            return playable
        } catch {
            print("🛑 Asset load failed:", error)
            return false
        }
    }

    // MARK: - Image loading (from local)
    private func loadImage(for ad: AdItemModel) async {
        if imageCache[ad.itemurl] != nil { return }

        let localURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl)!
        do {
            // Load from disk or network OFF the main thread
            let data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: localURL)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
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
            Task { @MainActor in
                self?.transitionToNextItem()
            }
        }
    }

    // MARK: - Transition
    private func transitionToNextItem() {
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
    @MainActor
    private func applyPendingPlaylistSafely() async {
        guard !pendingGroups.isEmpty else { return }

        print("📥 Applying NEW playlist safely with diff merging…")

        let oldGroups = groupedAds
        let newGroups = pendingGroups

        // STEP 1 — Preload only new assets (based on diff)
        await preloadNewItems(old: oldGroups, new: newGroups)

        // STEP 2 — Cleanup old unused files
        cleanupObsoleteFiles(keeping: newGroups)

        // STEP 3 — Reset memory state
        localURLs.removeAll()
        imageCache.removeAll()

        // STEP 4 — Rebuild localURLs using files on disk for new playlist
        for group in newGroups {
            for ad in group.ii {
                let fileName = URL(string: ad.itemurl)?.lastPathComponent ?? ""
                let path = adsCacheDir.appendingPathComponent(fileName).path

                if fileManager.fileExists(atPath: path) {
                    localURLs[ad.itemurl] = adsCacheDir.appendingPathComponent(fileName)
                }
            }
        }

        // STEP 5 — Apply playlist
        groupedAds = newGroups
        pendingGroups.removeAll()
        currentIndex = 0
        lastAppliedSync = Date()

        // STEP 6 — Decode ALL images into memory
        print("🖼️ Rebuilding in-memory image cache…")

        for (key, url) in localURLs {
            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png"].contains(ext),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                imageCache[key] = img
            }
        }

        print("🎉 NEW playlist ready — begin playback")

        playCurrentGroup()
    }

    // MARK: - Auto Sync
    func startAutoSync(screenId: String) {
        syncTimer = Timer.scheduledTimer(withTimeInterval: repeatInTime, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncAds(with: screenId)
            }
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
                        await self.applyPendingPlaylistSafely()
//                        await self.preloadPendingGroups()
                    }
                    
                case .failure(let error):
                    print("❌ Sync failed:", error.localizedDescription)
                }
            }
        }
    }

    /// Returns only NEW ads that do NOT exist in old playlist.
    private func computeDiff(old oldGroups: [AdSequenceGroup],
                             new newGroups: [AdSequenceGroup]) -> [AdItemModel] {

        let oldAds = Set(oldGroups.flatMap { $0.ii.map { $0.itemurl } })
        let newAds = newGroups.flatMap { $0.ii }

        return newAds.filter { !oldAds.contains($0.itemurl) }
    }

    private func cleanupObsoleteFiles(keeping groups: [AdSequenceGroup]) {
        let keepFiles = Set(groups.flatMap { group in
            group.ii.compactMap { URL(string: $0.itemurl)?.lastPathComponent.lowercased() }
        })

        if let files = try? fileManager.contentsOfDirectory(atPath: adsCacheDir.path) {
            for file in files {
                if !keepFiles.contains(file.lowercased()) {
                    let url = adsCacheDir.appendingPathComponent(file)
                    try? fileManager.removeItem(at: url)
                    print("🗑️ Removed obsolete file:", file)
                }
            }
        }
    }

    private func preloadNewItems(old oldGroups: [AdSequenceGroup],
                                 new newGroups: [AdSequenceGroup]) async {
        
        let filteredGroups = await filterUnplayableAds(newAds: newGroups)        // <-- new: remove bad videos before playback
        let newItems = computeDiff(old: oldGroups, new: filteredGroups)
        print("🆕 Found \(newItems.count) NEW items to download")

        for ad in newItems {
            if let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
        }

        print("✅ Preloading new items completed")
    }

    // MARK: - Stop
    func stop() {
        activePlayer?.pause()
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        syncTimer?.invalidate()
    }
}
