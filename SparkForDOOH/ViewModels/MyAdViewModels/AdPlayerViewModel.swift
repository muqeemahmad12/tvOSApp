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
    @Published var contentOpacity: Double = 1.0  // For crossfade transitions
    /// Controls when overlay UI (ticker/time/logo) should appear.
    @Published var isPlayerReadyForOverlay = false

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
    
    // MARK: - Sync failure tracking
    fileprivate var consecutiveSyncFailures = 0
    fileprivate let maxSyncFailuresBeforeFallback = 5
    @Published var isUsingFallbackContent = false
    @Published var isPlayingSafeContent = false
    
    // MARK: - Background download tracking
    fileprivate var isPendingDownloadComplete = false
    fileprivate var isDownloadingInBackground = false

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
    
    /// Hard cap for on-disk ads cache (bytes). LRU eviction will run when exceeded.
    fileprivate let maxAdsCacheSizeBytes: UInt64

    init(config: AppConfig = .current, disablePreloadingAndValidation: Bool = false) {
        self.screenId = config.screenId
        self.repeatInTime = config.playlistRepeatInterval
        self.disablePreloadingAndValidation = disablePreloadingAndValidation
        self.maxAdsCacheSizeBytes = config.adsCacheMaxBytes
    }
}

// MARK: - Public API
extension AdPlayerViewModel {
    /// Entry point: prepare assets, then begin playback and auto-sync.
    func startPlayback(with groups: [AdSequenceGroup]) {
        // Handle empty playlist with safe content fallback
        if groups.isEmpty {
            if groupedAds.isEmpty {
                print("⚠️ Empty playlist received - waiting for content (no playback)")
                isPreloading = false
            } else {
                print("ℹ️ Empty playlist received - keeping existing cached playback")
            }
            return
        }
        
        // If we were showing placeholder/safe content, allow real content to take over
        if isPlayingSafeContent {
            print("✅ Real content received - replacing safe content fallback")
            isPlayingSafeContent = false
            isPreloading = false  // Reset so we can start real playback
        }
        
        // Prevent multiple simultaneous startPlayback calls (but not if we have no content yet)
        guard !isPreloading else {
            print("⏳ Already preloading - ignoring duplicate startPlayback call")
            return
        }
        
        // If we already have REAL content playing, store as pending instead
        if !groupedAds.isEmpty && currentGroup != nil && !isPlayingSafeContent {
            print("🔄 Already playing - storing as pending playlist")
            pendingGroups = groups
            return
        }

        currentIndex = 0

        // In test mode, keep this synchronous and skip heavy operations.
        if disablePreloadingAndValidation {
            groupedAds = groups
            playCurrentGroup()
            return
        }

        // Set preloading flag BEFORE Task to prevent race conditions
        isPreloading = true
        isPlayerReadyForOverlay = false
        
        Task {
            groupedAds = await filterUnplayableAds(newAds: groups) // remove bad videos before playback
            await preloadAllAssets()  // This manages isPreloading internally
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
        isPlayerReadyForOverlay = false
    }
    
    /// Handle empty playlist by falling back to safe content
    private func handleEmptyPlaylistFallback() {
        isPlayingSafeContent = true
        
        // Try to use safe content from bundle
        if let safeGroup = SafeContentManager.shared.getSafeContentGroup() {
            print("🛡️ Using bundled safe content as fallback")
            groupedAds = [safeGroup]
            currentIndex = 0
            playCurrentGroup()
            
            // Still try to sync in case content becomes available
            startAutoSync(screenId: screenId)
        } else {
            print("⚠️ No safe content available - showing placeholder")
            // The view will show PlayerLoadingPlaceholderView
            // Note: Do NOT set isPreloading = true here, as it would block real content from loading
            
            // Keep trying to sync
            startAutoSync(screenId: screenId)
        }
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

        // Enforce disk cap after downloads (protect currently referenced assets)
        enforceCacheSizeLimit(keeping: groupedAds)

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

        // If cached already on disk → load into memory and return
        if fileManager.fileExists(atPath: destination.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: destination.path),
               let fileSize = attrs[.size] as? UInt64 {
                print("📦 Using cached file (\(formatBytes(fileSize))):", fileName)
            }
            // Still need to cache images in memory!
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".jpeg") {
                if let data = try? Data(contentsOf: destination),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        storeImage(img, forKey: remoteURLString)
                    }
                    print("🖼️ Loaded cached image into memory:", fileName)
                }
            }
            return destination
        }

        do {
            print("⬇️ Downloading:", fileName)
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: destination)
            print("💾 Saved: \(fileName) (\(formatBytes(UInt64(data.count))))")

            // Decode & cache images immediately
            if fileName.hasSuffix(".jpg") || fileName.hasSuffix(".png") || fileName.hasSuffix(".jpeg"),
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

        // Enforce cap using union of old+new groups to avoid evicting active assets
        enforceCacheSizeLimit(keeping: oldGroups + filteredGroups)

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

                // For video, require a minimally valid URL. Do NOT drop videos based on playability checks here;
                // rely on AVPlayer at runtime to attempt playback, even if offline during preload.
                guard URL(string: ad.itemurl) != nil || localURLs[ad.itemurl] != nil else {
                    print("❌ Removing (invalid URL):", ad.itemurl)
                    continue
                }

                keptAds.append(ad)
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
        isPlayerReadyForOverlay = true
        
        // Update heartbeat with current playback status
        let currentAdId = group.ii.first?.itemid ?? ""
        HeartbeatAPI.shared.updatePlaybackStatus(
            sequenceIndex: group.sequence,
            adId: currentAdId,
            isPlaying: true
        )

        let ads = group.ii

        // 1. Try video first ONLY if it's first in list
        if let first = ads.first,
           first.assettype.lowercased() == "video" {
            // Track impression for video
            trackImpression(for: first)
            playVideo(first)
            return
        }

        // 2. If no leading video → show images for group duration
        // Track impressions for all images in the group
        for ad in ads where ad.assettype.lowercased() == "image" {
            trackImpression(for: ad)
        }
        
        startGroupTimer()

        // Preload images into memory
        Task {
            for ad in group.ii where ad.assettype.lowercased() == "image" {
                await loadImage(for: ad)
            }
        }
    }

    func playVideo(_ ad: AdItemModel) {
        let cachedURL = localURLs[ad.itemurl]
        let remoteURL = URL(string: ad.itemurl)
        
        guard let playURL = cachedURL ?? remoteURL else {
            print("❌ Invalid URL:", ad.itemurl)
            transitionToNextItem()
            return
        }
        
        // Log which URL we're using
        if cachedURL != nil {
            print("▶️ Playing from cache: \(playURL.lastPathComponent)")
        } else {
            print("⚠️ Playing from REMOTE (not cached): \(ad.itemurl)")
        }

        activePlayer = AVPlayer(url: playURL)
        activePlayer?.play()
        
        // Clear Now Playing info to suppress system UI
        MediaSessionHelper.shared.clearNowPlayingInfo()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: activePlayer?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Track video completion
                self?.trackCompletion(for: ad)
                self?.transitionToNextItem()
            }
        }
    }
    
    // MARK: - Impression Tracking
    
    func trackImpression(for ad: AdItemModel) {
        guard !disablePreloadingAndValidation else { return }
        if let trackers = ad.trackerlist, !trackers.isEmpty {
            TrackerService.shared.fire(urls: trackers)
        }
    }
    
    func trackCompletion(for ad: AdItemModel) {
        guard !disablePreloadingAndValidation else { return }
        if let trackers = ad.trackerlist, !trackers.isEmpty {
            TrackerService.shared.fire(urls: trackers)
        }
    }
    
    func trackImageViewComplete(for ad: AdItemModel, duration: Int) {
        guard !disablePreloadingAndValidation else { return }
        if let trackers = ad.trackerlist, !trackers.isEmpty {
            TrackerService.shared.fire(urls: trackers)
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

    /// Fallback timer if no video (10 seconds for image groups).
    func startGroupTimer() {
        timer?.invalidate()
        let duration = 20
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Track view complete for all images in the group
                if let group = self?.currentGroup {
                    for ad in group.ii where ad.assettype.lowercased() == "image" {
                        self?.trackImageViewComplete(for: ad, duration: duration)
                    }
                }
                self?.transitionToNextItem()
            }
        }
    }

    /// Advance to the next group or loop / apply new playlist.
    func transitionToNextItem() {
        currentIndex += 1

        if currentIndex >= groupedAds.count {
            print("🔁 Loop finished.")

            // Apply pending playlist as soon as downloads are complete (no delay)
            if !pendingGroups.isEmpty, isPendingDownloadComplete {
                print("📥 Downloads complete - applying new playlist safely…")
                Task {
                    await applyPendingPlaylistSafely()
                }
                return
            } else if !pendingGroups.isEmpty && !isPendingDownloadComplete {
                print("⏳ Downloads still in progress - continuing current playlist")
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
                
                // Store pending groups
                pendingGroups = response.groupedAds
                isPendingDownloadComplete = false
                
                // Cache the playlist for offline use
                PlaylistCacheService.shared.savePlaylist(response.groupedAds)
                
                // Start background download immediately (don't wait for loop to finish)
                await startBackgroundDownload()
                
                // Reset failure counter on success
                consecutiveSyncFailures = 0
                isUsingFallbackContent = false
                
                // Update heartbeat with last sync time
                HeartbeatAPI.shared.updateLastSyncTime()
            } catch {
                consecutiveSyncFailures += 1
                print("❌ Sync failed (\(consecutiveSyncFailures)/\(maxSyncFailuresBeforeFallback)):", error.localizedDescription)
                
                // Check if we should switch to fallback mode
                if consecutiveSyncFailures >= maxSyncFailuresBeforeFallback {
                    handleSyncFailureFallback()
                }
            }
        }
    }
    
    /// Download new assets in background while current playlist continues playing
    func startBackgroundDownload() async {
        guard !pendingGroups.isEmpty, !isDownloadingInBackground else { return }
        
        isDownloadingInBackground = true
        print("📥 Starting background download for new playlist...")
        
        let oldGroups = groupedAds
        let newGroups = pendingGroups
        
        // Download only new items (diff)
        await preloadNewItems(old: oldGroups, new: newGroups)
        
        isDownloadingInBackground = false
        isPendingDownloadComplete = true
        print("✅ Background download complete - ready to apply")
        
        // If we are not actively playing real content, apply immediately
        if groupedAds.isEmpty || isPlayingSafeContent || currentGroup == nil {
            await applyPendingPlaylistSafely()
        }
    }
    
    /// Handle fallback after 5 consecutive sync failures
    private func handleSyncFailureFallback() {
        guard !isUsingFallbackContent else { return }
        
        isUsingFallbackContent = true
        print("⚠️ 5 consecutive sync failures - continuing with cached content")
        
        // Continue playing cached content - no action needed
        // The existing playlist will keep looping
        // Could show a subtle indicator in UI if needed
        
        // Log to Sentry for monitoring
        let error = NSError(domain: "com.sparkfordooh.sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync fallback activated after \(maxSyncFailuresBeforeFallback) failures"])
        SentryService.shared.capture(error: error)
    }

    func applyPendingPlaylistSafely() async {
        guard !pendingGroups.isEmpty else { return }

        print("📥 Applying NEW playlist (downloads already complete)…")

        let newGroups = pendingGroups

        // STEP 1 — Cleanup old unused files (downloads already done in background)
        cleanupObsoleteFiles(keeping: newGroups)

        // STEP 3 — Reset memory state
        localURLs.removeAll()
        imageCache.removeAll()

        // STEP 4 — Rebuild localURLs using files on disk for new playlist
        print("🔍 Rebuilding localURLs for \(newGroups.flatMap { $0.ii }.count) ads...")
        var foundCount = 0
        var missingCount = 0
        
        for group in newGroups {
            for ad in group.ii {
                // Use lowercased filename to match how downloadAsset saves files
                let fileName = URL(string: ad.itemurl)?.lastPathComponent.lowercased() ?? ""
                let localURL = adsCacheDir.appendingPathComponent(fileName)

                if fileManager.fileExists(atPath: localURL.path) {
                    localURLs[ad.itemurl] = localURL
                    foundCount += 1
                } else {
                    print("⚠️ File NOT found: \(fileName) at \(localURL.path)")
                    missingCount += 1
                }
            }
        }
        print("📊 Rebuild complete: \(foundCount) found, \(missingCount) missing")

        // STEP 5 — Apply playlist
        groupedAds = newGroups
        pendingGroups.removeAll()
        isPendingDownloadComplete = false  // Reset for next sync
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

    /// Human-readable size formatter.
    func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.2f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.2f GB", gb)
    }

    /// Enforce a hard size cap on AdsCache using LRU eviction (oldest access/modification first).
    func enforceCacheSizeLimit(keeping groups: [AdSequenceGroup]) {
        let keepFiles = Set(groups.flatMap { group in
            group.ii.compactMap { URL(string: $0.itemurl)?.lastPathComponent.lowercased() }
        })

        guard let files = try? fileManager.contentsOfDirectory(
            at: adsCacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        var entries: [(url: URL, size: UInt64, date: Date)] = []
        var totalSize: UInt64 = 0

        for url in files {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey])
            let size = UInt64(values?.fileSize ?? 0)
            totalSize += size
            let date = values?.contentAccessDate ?? values?.contentModificationDate ?? Date.distantPast
            entries.append((url: url, size: size, date: date))
        }

        guard totalSize > maxAdsCacheSizeBytes else { return } // already within cap

        var remainingSize = totalSize
        let sorted = entries.sorted { $0.date < $1.date } // oldest first

        for entry in sorted {
            if remainingSize <= maxAdsCacheSizeBytes { break }
            let name = entry.url.lastPathComponent.lowercased()
            if keepFiles.contains(name) {
                continue // don't evict active/pending assets
            }
            do {
                try fileManager.removeItem(at: entry.url)
                remainingSize -= entry.size
                print("🗑️ LRU eviction:", name)
            } catch {
                print("⚠️ Failed to evict \(name):", error.localizedDescription)
            }
        }

        if remainingSize > maxAdsCacheSizeBytes {
            print("⚠️ AdsCache still exceeds cap after eviction. Consider increasing maxAdsCacheSizeBytes or reducing asset sizes.")
        } else {
            let remainingMB = Double(remainingSize) / (1024 * 1024)
            print("✅ AdsCache within cap. Current size: \(String(format: "%.1f MB", remainingMB))")
        }
    }
}


