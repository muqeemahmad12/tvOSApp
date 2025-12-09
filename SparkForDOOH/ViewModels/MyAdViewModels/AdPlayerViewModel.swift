//
//  AdPlayerViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import AVKit
import SwiftUI

/// Orchestrates ad playback: preloads assets, manages the current group,
/// loops through the playlist, and periodically syncs updated content.
@MainActor
final class AdPlayerViewModel: ObservableObject {
    // MARK: - Published state
    @Published var currentGroup: AdSequenceGroup?
    @Published var groupedAds: [AdSequenceGroup] = []
    @Published var imageCache: [String: UIImage] = [:]
    @Published var slideOffset: CGFloat = 0.0
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0.0
    @Published var errorMessage: String?

    // MARK: - Private state
    fileprivate var pendingGroups: [AdSequenceGroup] = []
    fileprivate var currentIndex = 0
    var activePlayer: AVPlayer?
    fileprivate var timer: Timer?
    fileprivate var syncTimer: Timer?
    fileprivate var reqNum = 1
    fileprivate var screenId: String
    fileprivate var repeatInTime: TimeInterval
    fileprivate var lastAppliedSync: Date = .distantPast

    // MARK: - File Manager helpers
    fileprivate var fileManager: FileManager { .default }
    fileprivate var adsCacheDir: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AdsCache")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    fileprivate var localURLs: [String: URL] = [:]

    /// When true (used mainly in unit tests), skips network-heavy preloading,
    /// video playability checks, and auto-sync to keep `startPlayback` deterministic.
    fileprivate let disablePreloadingAndValidation: Bool

    /// Soft cap for in-memory image cache to avoid unbounded growth with very large playlists.
    fileprivate let maxImageCacheEntries = 200

    init(config: AppConfig = .current, disablePreloadingAndValidation: Bool = false) {
        self.screenId = config.screenId
        self.repeatInTime = config.playlistRepeatInterval
        self.disablePreloadingAndValidation = disablePreloadingAndValidation
    }
}

// MARK: - Public API
extension AdPlayerViewModel {
    /// Entry point: prepare assets, then begin playback and auto-sync.
    func startPlayback(with groups: [AdSequenceGroup]) {
        guard !groups.isEmpty else {
            print("⚠️ No groups to play.")
            return
        }

        currentIndex = 0

        // In test mode, keep this synchronous and skip heavy operations.
        if disablePreloadingAndValidation {
            groupedAds = groups
            playCurrentGroup()
            return
        }

        Task {
            groupedAds = await filterUnplayableAds(newAds: groups) // remove bad videos before playback
            await preloadAllAssets()
            playCurrentGroup()
            startAutoSync(screenId: screenId)
        }
    }

    /// Stop playback and any timers.
    func stop() {
        activePlayer?.pause()
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        syncTimer?.invalidate()
    }
}

// MARK: - Preloading & Assets
private extension AdPlayerViewModel {
    /// Preload all assets in the current playlist.
    func preloadAllAssets() async {
        isPreloading = true
        preloadProgress = 0.0
        localURLs.removeAll()

        let allAds = groupedAds.flatMap { $0.ii }
        let total = Double(allAds.count)
        var completed = 0.0

        for ad in allAds {
            // If we ever re-enable size checks, this is where we'd skip huge assets.
//            if ad.isTooLarge {
//                print("⏭️ Skipping large asset (\(ad.itemsize ?? \"unknown\")) — \(ad.itemurl)")
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

    /// Download a single asset and persist it to disk.
    func downloadAsset(_ remoteURLString: String) async -> URL? {
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

            // Decode & cache images immediately
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png"),
               let img = UIImage(data: data) {
                await MainActor.run {
                    storeImage(img, forKey: remoteURLString)
                }
                print("🖼️ Cached image during download:", fileName)
            }

            return destination
        } catch {
            print("❌ Failed to download \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns only NEW ads that do NOT exist in old playlist.
    func computeDiff(old oldGroups: [AdSequenceGroup],
                     new newGroups: [AdSequenceGroup]) -> [AdItemModel] {
        let oldAds = Set(oldGroups.flatMap { $0.ii.map { $0.itemurl } })
        let newAds = newGroups.flatMap { $0.ii }
        return newAds.filter { !oldAds.contains($0.itemurl) }
    }

    func cleanupObsoleteFiles(keeping groups: [AdSequenceGroup]) {
        let keepFiles = Set(groups.flatMap { group in
            group.ii.compactMap { URL(string: $0.itemurl)?.lastPathComponent.lowercased() }
        })

        if let files = try? fileManager.contentsOfDirectory(atPath: adsCacheDir.path) {
            for file in files where !keepFiles.contains(file.lowercased()) {
                let url = adsCacheDir.appendingPathComponent(file)
                try? fileManager.removeItem(at: url)
                print("🗑️ Removed obsolete file:", file)
            }
        }
    }

    func preloadNewItems(old oldGroups: [AdSequenceGroup],
                         new newGroups: [AdSequenceGroup]) async {
        let filteredGroups = await filterUnplayableAds(newAds: newGroups)
        let newItems = computeDiff(old: oldGroups, new: filteredGroups)
        print("🆕 Found \(newItems.count) NEW items to download")

        for ad in newItems {
            if let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
        }

        print("✅ Preloading new items completed")
    }
}

// MARK: - Playback helpers
private extension AdPlayerViewModel {
    /// Remove unplayable video items & empty groups.
    func filterUnplayableAds(newAds: [AdSequenceGroup]) async -> [AdSequenceGroup] {
        print("🔎 Validating playable videos before starting playback…")
        var newGroups: [AdSequenceGroup] = []

        for group in newAds {
            var keptAds: [AdItemModel] = []

            for ad in group.ii {
                // Images are always kept
                if ad.assettype.lowercased() != "video" {
                    keptAds.append(ad)
                    continue
                }

                // For video, require a local or remote URL
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

        return newGroups
    }

    /// Play the current group (from local cache).
    func playCurrentGroup() {
        guard currentIndex < groupedAds.count else { return }
        let group = groupedAds[currentIndex]
        currentGroup = group
        print("▶️ Playing group \(group.sequence) — \(group.ii.count) ads")

        let ads = group.ii

        // 1. Try video first ONLY if it's first in list
        if let first = ads.first,
           first.assettype.lowercased() == "video" {
            playVideo(first)
            return
        }

        // 2. If no leading video → show images for group duration
        startGroupTimer()

        // Preload images into memory
        Task {
            for ad in group.ii where ad.assettype.lowercased() == "image" {
                await loadImage(for: ad)
            }
        }
    }

    func playVideo(_ ad: AdItemModel) {
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
            let playable = try await asset.load(.isPlayable)
            return playable
        } catch {
            print("🛑 Asset load failed:", error)
            return false
        }
    }

    /// Load image from local disk/remote and cache it in memory.
    func loadImage(for ad: AdItemModel) async {
        if imageCache[ad.itemurl] != nil { return }

        let localURL = localURLs[ad.itemurl] ?? URL(string: ad.itemurl)!

        do {
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
                await MainActor.run { storeImage(image, forKey: ad.itemurl) }
                print("🖼️ Cached image:", ad.itemurl)
            }
        } catch {
            print("❌ Image load failed:", error)
        }
    }

    /// Fallback timer if no video.
    func startGroupTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.transitionToNextItem()
            }
        }
    }

    /// Advance to the next group or loop / apply new playlist.
    func transitionToNextItem() {
        currentIndex += 1

        if currentIndex >= groupedAds.count {
            print("🔁 Loop finished.")

            let now = Date()
            if now.timeIntervalSince(lastAppliedSync) >= repeatInTime,
               !pendingGroups.isEmpty {
                print("📥 Time to apply new playlist — preparing safely…")
                Task {
                    await applyPendingPlaylistSafely()
                }
                return
            }

            currentIndex = 0
        }

        slideOffset = 0
        playCurrentGroup()
    }
}

// MARK: - Sync helpers
private extension AdPlayerViewModel {
    func startAutoSync(screenId: String) {
        syncTimer = Timer.scheduledTimer(withTimeInterval: repeatInTime, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncAds(with: screenId)
            }
        }
    }

    func syncAds(with screenId: String) {
        reqNum += 1
        print("🌐 Running periodic API sync... with reqNum: \(reqNum)")

        Task {
            do {
                let response = try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                print("🔄 Sync data fetched: \(response.groupedAds.count) groups")
                pendingGroups = response.groupedAds
                await applyPendingPlaylistSafely()
            } catch {
                print("❌ Sync failed:", error.localizedDescription)
            }
        }
    }

    func applyPendingPlaylistSafely() async {
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
                storeImage(img, forKey: key)
            }
        }

        print("🎉 NEW playlist ready — begin playback")
        playCurrentGroup()
    }
}

// MARK: - Image cache helpers
private extension AdPlayerViewModel {
    func storeImage(_ image: UIImage, forKey key: String) {
        // Simple cap-based eviction (approximate LRU by dropping an arbitrary key).
        if imageCache.count >= maxImageCacheEntries,
           let removeKey = imageCache.keys.first {
            imageCache.removeValue(forKey: removeKey)
        }
        imageCache[key] = image
    }
}


