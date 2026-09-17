//
//  AdPlayerViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import AVKit
import SwiftUI

extension Notification.Name {
    /// Posted when periodic quest sync applies a non-empty playlist to the player.
    static let questPlaylistApplied = Notification.Name("com.doceree.sparkfordooh.questPlaylistApplied")
    /// Posted when quest returns `status: NO_DATA_FOUND` — force Waiting for Content.
    static let questNoDataFound = Notification.Name("com.doceree.sparkfordooh.questNoDataFound")
    /// Posted when playback caches are wiped (not used on deactivation anymore; kept for manual/other clears).
    static let playbackCachesClearedOnDeactivation = Notification.Name("com.doceree.sparkfordooh.playbackCachesClearedOnDeactivation")
}

/// Orchestrates ad playback: preloads assets, manages the current group,
/// loops through the playlist, and periodically syncs updated content.
@MainActor
final class AdPlayerViewModel: ObservableObject {
    // MARK: - Published state
    @Published var currentGroup: AdSequenceGroup?
    @Published var groupedAds: [AdSequenceGroup] = []
    @Published var imageCache: [String: UIImage] = [:]
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0.0
    /// Controls when overlay UI (ticker/time/logo) should appear.
    @Published var isPlayerReadyForOverlay = false
    /// True when there is nothing displayable (empty / Banner-only / etc.) — show waiting UI.
    @Published var isWaitingForPlayableContent = false
    /// When false with a video+image group, skip L-shape companions and play video fullscreen.
    @Published var showsLShapeCompanions = true
    /// Main video/image failed — show branded fallback in main slot (L-shape) or hold fullscreen.
    @Published var showWhiteMainSlot = false
    /// Main creative still buffering/loading — show a compact loader (not a blank white screen).
    @Published var isMainSlotLoading = false
    /// Animate L↔fullscreen only for intentional duration collapse (not corrupt → fullscreen).
    @Published var animateLShapeLayoutChange = false

    // MARK: - Private state
    fileprivate var pendingGroups: [AdSequenceGroup] = []
    fileprivate var currentIndex = 0
    var activePlayer: AVPlayer?
    fileprivate var timer: Timer?
    fileprivate var syncTimer: Timer?
    fileprivate var reqNum = 1
    fileprivate var screenId: String
    fileprivate var repeatInTime: TimeInterval
    fileprivate var playerItemStatusObservation: NSKeyValueObservation?
    fileprivate var videoEndObserver: NSObjectProtocol?
    fileprivate var videoFailedObserver: NSObjectProtocol?
    /// Prevents double-advance when both status=.failed and FailedToPlayToEndTime fire.
    fileprivate var isHandlingCorruptMain = false
    /// Prevents duplicate impression pixels for the same creative within one group play.
    fileprivate var firedImpressionKeys: Set<String> = []
    /// Counts corrupt skips in one full playlist pass; if all fail → waiting (keep disk cache).
    fileprivate var consecutiveCorruptSkips = 0
    /// When companion image duration exceeds video length, restart video until L-shape collapses.
    fileprivate var shouldRepeatVideoWhileLShape = false
    /// Companion hold (seconds) while L-shape is active — used once measured video duration is known.
    fileprivate var lShapeCompanionDurationSeconds: Int?
    /// When the timed L-shape hold began (for equal-duration / repeat boundary checks).
    fileprivate var lShapeHoldStartedAt: Date?
    /// Prevents double next-item from L-timer and video-end racing at an equal boundary.
    fileprivate var isFinishingLShapeGroup = false
    /// Bumped to ignore stale `DidPlayToEndTime` after L-scale / advance.
    fileprivate var videoEndEpoch: UInt64 = 0
    /// Last measured media duration (seconds) for the current main video.
    fileprivate var measuredMainVideoDuration: Double?
    /// Creative currently attached to `activePlayer` (for re-binding end observer after L-scale).
    fileprivate var activeVideoAd: AdItemModel?
    
    // MARK: - Sync failure tracking
    fileprivate var consecutiveSyncFailures = 0
    fileprivate let maxSyncFailuresBeforeFallback = 5
    @Published var isUsingFallbackContent = false
    
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

    /// True after first `playCurrentGroup` in this player session (for Sentry playback start / stop pairing).
    fileprivate var playbackSessionReportedToSentry = false
    
    /// Hard cap for on-disk ads cache (bytes). LRU eviction will run when exceeded.
    fileprivate let maxAdsCacheSizeBytes: UInt64

    init(config: AppConfig = .current, screenId: String? = nil, disablePreloadingAndValidation: Bool = false) {
        self.screenId = screenId ?? config.screenId
        self.repeatInTime = config.playlistRepeatInterval
        self.disablePreloadingAndValidation = disablePreloadingAndValidation
        self.maxAdsCacheSizeBytes = config.adsCacheMaxBytes
    }
}

// MARK: - Public API
extension AdPlayerViewModel {
    /// Entry point: prepare assets, then begin playback and auto-sync.
    func startPlayback(with groups: [AdSequenceGroup]) {
        // Empty / unplayable: keep current playlist + disk cache until ≥1 playable item arrives.
        if groups.isEmpty {
            if hasActivePlayablePlaylist {
                print("ℹ️ Empty/unplayable playlist ignored — keeping current playlist and cache")
            } else {
                print("⚠️ No playable playlist available — waiting for content (disk cache kept)")
                enterWaitingForPlayableContent()
            }
            if !disablePreloadingAndValidation {
                startAutoSync(screenId: screenId)
            }
            return
        }
        
        // Prevent multiple simultaneous startPlayback calls (but not if we have no content yet)
        guard !isPreloading else {
            print("⏳ Already preloading - ignoring duplicate startPlayback call")
            return
        }
        
        // If we already have content playing, only replace when new playlist has ≥1 playable item.
        if hasActivePlayablePlaylist {
            let playable = Self.displayableGroups(from: groups)
            guard !playable.isEmpty else {
                print("ℹ️ New quest has no playable image/video — keeping current playlist and cache")
                return
            }
            print("🔄 Already playing — downloading replacement playlist (\(playable.count) groups)")
            pendingGroups = playable
            isPendingDownloadComplete = false
            if !disablePreloadingAndValidation {
                Task {
                    await startBackgroundDownload()
                }
            } else {
                Task {
                    await applyPendingPlaylistSafely()
                }
            }
            return
        }

        currentIndex = 0

        // In test mode, keep this synchronous and skip heavy operations.
        if disablePreloadingAndValidation {
            let playable = Self.displayableGroups(from: groups)
            guard !playable.isEmpty else {
                enterWaitingForPlayableContent()
                return
            }
            isWaitingForPlayableContent = false
            consecutiveCorruptSkips = 0
            groupedAds = playable
            playCurrentGroup()
            return
        }

        // Set preloading flag BEFORE Task to prevent race conditions
        isPreloading = true
        isPlayerReadyForOverlay = false
        
        Task {
            let playable = await filterUnplayableAds(newAds: groups) // drops Banner / zip / invalid
            guard !playable.isEmpty else {
                // Nothing playable and nothing already playing → wait; never wipe disk.
                print("⚠️ No playable image/video creatives — waiting (playlist/cache unchanged on disk)")
                enterWaitingForPlayableContent()
                startAutoSync(screenId: screenId)
                return
            }
            isWaitingForPlayableContent = false
            consecutiveCorruptSkips = 0
            groupedAds = playable
            await preloadAllAssets()  // This manages isPreloading internally
            playCurrentGroup()
            startAutoSync(screenId: screenId)
        }
    }

    /// True when we have an in-memory playlist that is actively (or was) playable.
    private var hasActivePlayablePlaylist: Bool {
        !isWaitingForPlayableContent && !groupedAds.isEmpty && currentGroup != nil
    }

    /// Stop playback UI and wait for the next quest to deliver image/video creatives.
    /// Never clears AdsCache or playlist JSON — those stay until a quest with ≥1 playable item is applied.
    func enterWaitingForPlayableContent() {
        isWaitingForPlayableContent = true
        isPreloading = false
        isPlayerReadyForOverlay = false
        consecutiveCorruptSkips = 0
        clearVideoObservers()
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        activePlayer = nil
        currentGroup = nil
        // Clear only in-memory playback state for the waiting UI.
        // Disk AdsCache + saved playlist JSON are left untouched.
        groupedAds = []
        pendingGroups.removeAll()
        isPendingDownloadComplete = false
        // Keep sync alive so the next quest can restore content.
        if !disablePreloadingAndValidation {
            startAutoSync(screenId: screenId)
        }
        print("⏳ Waiting for content — disk playlist/cache unchanged until ≥1 playable item")
    }

    /// Stop playback and any timers.
    func stop() {
        clearVideoObservers()
        activePlayer?.pause()
        activePlayer = nil
        timer?.invalidate()
        timer = nil
        syncTimer?.invalidate()
        isPlayerReadyForOverlay = false
        if playbackSessionReportedToSentry {
            playbackSessionReportedToSentry = false
            SentryService.shared.track(SentryAnalyticsEvent.playbackStopped, attributes: [:])
            SentryService.shared.breadcrumb(category: "playback", message: "stopped", data: [:])
        }
    }
    
    /// Resume playback when app returns to foreground (e.g. TV wake, app resume).
    /// Call from the view when scenePhase becomes .active.
    func resumePlayback() {
        guard !disablePreloadingAndValidation else { return }
        if activePlayer != nil, currentGroup != nil {
            activePlayer?.play()
            print("▶️ Resumed playback after app became active")
        }
    }

    /// Pause playback on deactivation — keep playlist + disk/memory caches for resume.
    func pauseForDeactivation() {
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        isPlayerReadyForOverlay = false
        print("⏸️ Playback paused for deactivation (cache kept)")
    }

    /// Resume existing playlist after ACTIVE; quest sync may update in the background.
    func resumeAfterReactivation() {
        isWaitingForPlayableContent = false
        isPlayerReadyForOverlay = true
        if activePlayer != nil, currentGroup != nil {
            activePlayer?.play()
            // Restart L-shape / image timers if needed for the current group.
            if let group = currentGroup {
                let images = group.lShapeCompanions
                let hasVideo = group.ii.contains { $0.isVideoType && $0.hasMinimumPlayableFields }
                if hasVideo, !images.isEmpty {
                    // Broken L-shape + healthy video → keep playing video fullscreen.
                    let companionBad = images.contains { isUnusableCompanion($0) }
                    showsLShapeCompanions = !companionBad && !showWhiteMainSlot
                    if showsLShapeCompanions {
                        scheduleLShapeCollapseIfNeeded(images: images)
                    }
                } else if !hasVideo {
                    // Image L-shape: only resume L layout when every image is still usable.
                    if images.count >= 2, images.contains(where: { isUnusableCompanion($0) }) {
                        print("⏭️ Image L-shape broken on resume — skipping group")
                        skipEntireCorruptGroup()
                        return
                    }
                    showsLShapeCompanions = images.count >= 2 && !showWhiteMainSlot
                    startGroupTimer()
                }
            }
            print("▶️ Resumed existing playlist after re-activation")
            return
        }
        if !groupedAds.isEmpty {
            currentIndex = min(max(currentIndex, 0), groupedAds.count - 1)
            playCurrentGroup()
            print("▶️ Restarted playlist group after re-activation")
            return
        }
        print("⚠️ No in-memory playlist after re-activation — waiting for quest/cache")
    }
}

// MARK: - Preloading & Assets
private extension AdPlayerViewModel {
    /// Preload all assets in the current playlist.
    func preloadAllAssets() async {
        isPreloading = true
        preloadProgress = 0.0
        localURLs.removeAll()
        imageCache.removeAll()

        let allAds = groupedAds.flatMap { $0.ii }
        let total = Double(max(allAds.count, 1))
        var completed = 0.0

        for ad in allAds {
            // Skip unplayable L-shape placeholders (zip/HTML5/etc.) — UI shows white.
            if ad.hasMinimumPlayableFields,
               let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
            completed += 1
            await MainActor.run { preloadProgress = completed / total }
        }

        // After successful download of this quest playlist: keep ONLY these creatives everywhere.
        retainOnlyCurrentPlaylist(groupedAds)

        await MainActor.run {
            isPreloading = false
            print("✅ All assets downloaded to \(adsCacheDir.lastPathComponent)")
        }
    }

    /// Download a single asset and persist it to disk.
    func downloadAsset(_ remoteURLString: String) async -> URL? {
        let normalized = AdItemModel.normalizedMediaURLString(remoteURLString)
        guard let remoteURL = URL(string: normalized) ?? {
            normalized.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        }() else {
            print("❌ Invalid media URL:", remoteURLString)
            return nil
        }
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

        guard NetworkMonitor.shared.canMakeNetworkCalls else {
            print("📵 Download skipped — no internet:", fileName)
            return nil
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
            group.ii
                .filter { $0.hasMinimumPlayableFields }
                .compactMap { $0.mediaURL?.lastPathComponent.lowercased() }
        })

        var removed = 0
        if let files = try? fileManager.contentsOfDirectory(atPath: adsCacheDir.path) {
            for file in files where !keepFiles.contains(file.lowercased()) {
                let url = adsCacheDir.appendingPathComponent(file)
                try? fileManager.removeItem(at: url)
                removed += 1
                print("🗑️ Removed obsolete file:", file)
            }
        }
        if removed > 0 {
            print("🗑️ Purged \(removed) unmatched AdsCache file(s); kept \(keepFiles.count) current playlist file(s)")
        }
    }

    /// After a successful playable quest download: storage must match ONLY this playlist
    /// (images-only, video-only, or mixed). Unmatched items are removed from disk + memory.
    func retainOnlyCurrentPlaylist(_ groups: [AdSequenceGroup]) {
        let keepURLs = Set(
            groups.flatMap { $0.ii.filter(\.hasMinimumPlayableFields).map(\.itemurl) }
        )

        // Memory — local URL map
        localURLs = localURLs.filter { keepURLs.contains($0.key) }

        // Memory — decoded images
        imageCache = imageCache.filter { keepURLs.contains($0.key) }

        // Disk — AdsCache files not in this playlist
        cleanupObsoleteFiles(keeping: groups)
        enforceCacheSizeLimit(keeping: groups)

        // Disk — playlist JSON must match this quest
        if !groups.isEmpty {
            PlaylistCacheService.shared.savePlaylist(groups)
        }

        print("📌 Storage aligned to current quest playlist: \(keepURLs.count) creative URL(s)")
    }

    func preloadNewItems(old oldGroups: [AdSequenceGroup],
                         new newGroups: [AdSequenceGroup]) async {
        let filteredGroups = await filterUnplayableAds(newAds: newGroups)
        let newItems = computeDiff(old: oldGroups, new: filteredGroups)
        print("🆕 Found \(newItems.count) NEW items to download")

        for ad in newItems where ad.hasMinimumPlayableFields {
            if let url = await downloadAsset(ad.itemurl) {
                localURLs[ad.itemurl] = url
            }
        }

        // Size cap against the NEW playlist only — old unmatched assets are purged on apply.
        enforceCacheSizeLimit(keeping: filteredGroups)

        print("✅ Preloading new items completed")
    }
}

// MARK: - Playback helpers
private extension AdPlayerViewModel {
    static func isDisplayableAsset(_ ad: AdItemModel) -> Bool {
        ad.isDisplayableAsset
    }

    static func displayableGroups(from groups: [AdSequenceGroup]) -> [AdSequenceGroup] {
        groups.displayableGroups()
    }

    /// Keep playable image/video items. In multi-item (L-shape) groups, also keep
    /// unplayable slots so the UI can show white in place (zip/HTML5/etc.).
    func filterUnplayableAds(newAds: [AdSequenceGroup]) async -> [AdSequenceGroup] {
        print("🔎 Validating displayable creatives before starting playback…")
        
        var newGroups: [AdSequenceGroup] = []

        for group in newAds.displayableGroups() {
            var keptAds: [AdItemModel] = []
            let isLShape = group.ii.count >= 2

            for ad in group.ii {
                if !ad.hasMinimumPlayableFields {
                    if isLShape {
                        print("⬜ Keeping unplayable L-shape slot as white placeholder:", ad.itemurl)
                        keptAds.append(ad)
                    }
                    continue
                }
                let type = ad.assettype.lowercased()
                if type == "image" {
                    keptAds.append(ad)
                    continue
                }
                guard ad.mediaURL != nil || localURLs[ad.itemurl] != nil else {
                    if isLShape {
                        print("⬜ Invalid video URL — white placeholder in L-shape:", ad.itemurl)
                        keptAds.append(ad)
                    } else {
                        print("❌ Removing (invalid URL):", ad.itemurl)
                    }
                    continue
                }
                keptAds.append(ad)
            }

            let hasPlayable = keptAds.contains(where: { $0.hasMinimumPlayableFields })
            if hasPlayable {
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
        // Skip ahead past any remaining non-displayable groups (defensive).
        while currentIndex < groupedAds.count {
            let candidate = groupedAds[currentIndex]
            if candidate.ii.contains(where: { Self.isDisplayableAsset($0) }) {
                break
            }
            print("⏭️ Skipping group \(candidate.sequence) — no image/video")
            currentIndex += 1
        }

        guard currentIndex < groupedAds.count else {
            enterWaitingForPlayableContent()
            return
        }

        let group = groupedAds[currentIndex]
        currentGroup = group
        isWaitingForPlayableContent = false
        showWhiteMainSlot = false
        isMainSlotLoading = false
        isHandlingCorruptMain = false
        firedImpressionKeys.removeAll()
        animateLShapeLayoutChange = false
        shouldRepeatVideoWhileLShape = false
        lShapeCompanionDurationSeconds = nil
        lShapeHoldStartedAt = nil
        isFinishingLShapeGroup = false
        measuredMainVideoDuration = nil
        activeVideoAd = nil
        videoEndEpoch &+= 1
        print("▶️ Playing group \(group.sequence) — \(group.ii.count) ads")
        isPlayerReadyForOverlay = true

        if !playbackSessionReportedToSentry, !disablePreloadingAndValidation {
            playbackSessionReportedToSentry = true
            SentryService.shared.track(
                SentryAnalyticsEvent.playbackStarted,
                attributes: [
                    "sequence": "\(group.sequence)",
                    "group_items": "\(group.ii.count)"
                ]
            )
            SentryService.shared.breadcrumb(
                category: "playback",
                message: "started",
                data: ["sequence": "\(group.sequence)"]
            )
        }
        
        // Update heartbeat with current playback status
        let currentAdId = group.ii.first?.itemid ?? ""
        HeartbeatAPI.shared.updatePlaybackStatus(
            sequenceIndex: group.sequence,
            adId: currentAdId,
            isPlaying: true
        )

        let ads = group.ii
        let companions = group.lShapeCompanions
        let video = ads.first { $0.isVideoType && $0.hasMinimumPlayableFields }
        let hasUnplayableVideoSlot = ads.contains { $0.isVideoType && !$0.hasMinimumPlayableFields }

        // Playable main video: stay fullscreen until companions prove healthy, then show L-shape.
        // Companion images are placeholders — if any fail, keep video fullscreen (do not skip).
        // Trackers fire only for creatives that actually display (never for corrupt).
        if let video {
            consecutiveCorruptSkips = 0
            animateLShapeLayoutChange = false
            let knownBadCompanion = companions.contains { !$0.hasMinimumPlayableFields }
            // Fullscreen immediately; loader covers buffer gap until readyToPlay.
            showsLShapeCompanions = false
            showWhiteMainSlot = false
            isMainSlotLoading = true
            if knownBadCompanion {
                print("📐 L-shape companion unplayable — main video fullscreen by default")
            }
            playVideo(video)
            guard !companions.isEmpty, !knownBadCompanion else { return }
            Task {
                await self.prefetchCompanions(companions)
                guard currentGroup?.sequence == group.sequence else { return }
                if companions.contains(where: { self.isUnusableCompanion($0) }) {
                    print("📐 L-shape broken, video OK — play video fullscreen")
                    self.animateLShapeLayoutChange = false
                    self.showsLShapeCompanions = false
                    return
                }
                self.animateLShapeLayoutChange = false
                self.showsLShapeCompanions = true
                for ad in companions where !self.isUnusableCompanion(ad) {
                    self.trackImpression(for: ad)
                }
                self.scheduleLShapeCollapseIfNeeded(images: companions)
            }
            return
        }

        // Unplayable main video (e.g. zip) + L-shape companions:
        // Healthy companions → branded fallback in main + keep L for duration.
        // Any companion corrupt → skip the group.
        if hasUnplayableVideoSlot && !companions.isEmpty {
            print("🖼️ Unplayable main video — verifying L-shape companions for fallback/skip")
            showWhiteMainSlot = true
            isMainSlotLoading = false
            animateLShapeLayoutChange = false
            showsLShapeCompanions = false
            activePlayer = nil
            Task {
                await self.prefetchCompanions(companions)
                guard currentGroup?.sequence == group.sequence else { return }
                if companions.contains(where: { self.isUnusableCompanion($0) }) {
                    print("⏭️ Corrupt video + broken L-shape — skipping group \(group.sequence)")
                    self.skipEntireCorruptGroup()
                    return
                }
                self.consecutiveCorruptSkips = 0
                self.animateLShapeLayoutChange = false
                self.showsLShapeCompanions = true
                self.showWhiteMainSlot = true
                for ad in companions where !self.isUnusableCompanion(ad) {
                    self.trackImpression(for: ad)
                }
                self.scheduleWhiteMainHoldThenAdvance(companions: companions)
            }
            return
        }

        // Image-only: L-shape (2+ images) requires every slot healthy.
        // If L-shape is broken (any corrupt) and main is an image → skip the whole group
        // (never fall back to fullscreen main image).
        let images = group.ii
        let isImageLShape = images.count >= 2
        animateLShapeLayoutChange = false
        showsLShapeCompanions = false
        showWhiteMainSlot = false
        isMainSlotLoading = true

        if isImageLShape, images.contains(where: { !$0.hasMinimumPlayableFields }) {
            print("⏭️ Image L-shape broken (unplayable slot) — skipping group \(group.sequence)")
            isMainSlotLoading = false
            skipEntireCorruptGroup()
            return
        }

        Task {
            let main = images.first
            let sideImages = Array(images.dropFirst())

            if let main, main.hasMinimumPlayableFields {
                await loadImage(for: main, timeout: 15)
                if self.imageCache[main.itemurl] != nil {
                    self.isMainSlotLoading = false
                    self.showWhiteMainSlot = false
                }
            }

            await self.prefetchCompanions(sideImages)
            guard currentGroup?.sequence == group.sequence else { return }

            let mainPlayable = main.map { $0.hasMinimumPlayableFields && self.imageCache[$0.itemurl] != nil } ?? false

            if isImageLShape {
                if images.contains(where: { self.isUnusableCompanion($0) }) {
                    print("⏭️ Image L-shape broken — skipping group \(group.sequence) (no fullscreen image fallback)")
                    self.skipEntireCorruptGroup()
                    return
                }
                self.consecutiveCorruptSkips = 0
                self.animateLShapeLayoutChange = false
                self.isMainSlotLoading = false
                self.showWhiteMainSlot = false
                self.showsLShapeCompanions = true
                for ad in images {
                    self.trackImpression(for: ad)
                }
                self.startGroupTimer()
                return
            }

            // Single fullscreen image
            if !mainPlayable {
                self.isMainSlotLoading = false
                self.showWhiteMainSlot = true
                self.consecutiveCorruptSkips = 0
                self.animateLShapeLayoutChange = false
                self.showsLShapeCompanions = false
                print("⬜ Main image corrupt — white fullscreen for duration")
                self.startGroupTimer()
                return
            }

            self.consecutiveCorruptSkips = 0
            self.animateLShapeLayoutChange = false
            self.isMainSlotLoading = false
            self.showWhiteMainSlot = false
            self.showsLShapeCompanions = false
            if let main {
                self.trackImpression(for: main)
            }
            self.startGroupTimer()
        }
    }

    /// Fast companion prefetch — short timeout so corrupt sides don't stall the main creative.
    func prefetchCompanions(_ companions: [AdItemModel]) async {
        for ad in companions where ad.hasMinimumPlayableFields {
            await loadImage(for: ad, timeout: 8)
        }
    }

    /// Companion/image is unusable when it lacks playable fields or image bytes failed to load.
    func isUnusableCompanion(_ ad: AdItemModel) -> Bool {
        if !ad.hasMinimumPlayableFields { return true }
        if ad.isImageType {
            return imageCache[ad.itemurl] == nil
        }
        return false
    }

    /// Hide L-shape panels and keep main (video/image/white) fullscreen.
    /// - Parameter animated: true only for normal companion-duration collapse.
    func collapseLShapeToMainFullscreen(animated: Bool = false) {
        timer?.invalidate()
        timer = nil
        animateLShapeLayoutChange = animated
        showsLShapeCompanions = false
        shouldRepeatVideoWhileLShape = false
        lShapeCompanionDurationSeconds = nil
        lShapeHoldStartedAt = nil
        consecutiveCorruptSkips = 0
        // Invalidate any DidPlayToEndTime that raced with this collapse (would advance immediately).
        videoEndEpoch &+= 1
        installVideoEndObserver(for: activeVideoAd, epoch: videoEndEpoch)
    }

    /// Every creative in the group failed — advance (or wait if the whole playlist is bad).
    func skipEntireCorruptGroup() {
        clearVideoObservers()
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        activePlayer = nil
        showWhiteMainSlot = false
        isMainSlotLoading = false
        showsLShapeCompanions = false
        animateLShapeLayoutChange = false
        shouldRepeatVideoWhileLShape = false
        lShapeCompanionDurationSeconds = nil
        lShapeHoldStartedAt = nil
        isHandlingCorruptMain = false

        consecutiveCorruptSkips += 1
        let total = max(groupedAds.count, 1)
        if consecutiveCorruptSkips >= total {
            print("⏳ All \(total) playlist item(s) unplayable at runtime — waiting (disk cache kept)")
            consecutiveCorruptSkips = 0
            enterWaitingForPlayableContent()
            return
        }
        transitionToNextItem()
    }

    /// Keep L-shape for companion `duration`, then either scale video fullscreen or advance.
    /// - Equal durations (or exact N× video loops filling the hold) → next item, no scale.
    /// - Video longer than hold (or mid-loop when hold ends) → remove L-shape and scale video.
    /// - Video shorter than hold → repeat until hold ends, then apply the rules above.
    func scheduleLShapeCollapseIfNeeded(images: [AdItemModel]) {
        timer?.invalidate()
        timer = nil
        consecutiveCorruptSkips = 0
        shouldRepeatVideoWhileLShape = false
        lShapeCompanionDurationSeconds = nil
        lShapeHoldStartedAt = nil
        guard !images.isEmpty else { return }
        guard let companionDuration = images.compactMap(\.duration).filter({ $0 > 0 }).max() else {
            print("📐 L-shape for full video (no companion duration from API)")
            return
        }
        lShapeCompanionDurationSeconds = companionDuration
        lShapeHoldStartedAt = Date()
        updateShouldRepeatVideoForLShape(companionDuration: companionDuration)
        print("📐 L-shape for \(companionDuration)s — on end: stop+next if repeating/equal; scale only if video clearly longer")
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(companionDuration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleLShapeCompanionDurationEnded(companionDuration: companionDuration)
            }
        }
    }

    /// L-shape image hold finished.
    /// Repetition / within ±1s of video length → stop video, next item, never scale.
    /// Scale only when video is clearly longer than the L-shape hold (no repeat needed).
    private func handleLShapeCompanionDurationEnded(companionDuration: Int) {
        guard activePlayer != nil, !showWhiteMainSlot, !isMainSlotLoading else { return }
        guard !isFinishingLShapeGroup else { return }
        // Already collapsed or advancing — ignore timer/video-end races.
        guard showsLShapeCompanions else { return }

        if let group = currentGroup {
            for ad in group.ii where ad.assettype.lowercased() == "image" {
                guard !isUnusableCompanion(ad) else { continue }
                trackImageViewComplete(for: ad, duration: companionDuration)
            }
        }

        if shouldScaleAfterLShapeHold(companionDuration: companionDuration) {
            let remaining = remainingMainVideoSeconds() ?? 0
            print("📐 L-shape ended — video longer than hold, \(String(format: "%.2f", remaining))s left, scaling fullscreen")
            collapseLShapeToMainFullscreen(animated: true)
        } else {
            let V = measuredMainVideoDuration ?? measuredMainVideoDurationSeconds()
            print("📐 L-shape ended — stop video & next item (no scale) V=\(V.map { String(format: "%.2f", $0) } ?? "?")s C=\(companionDuration)s repeat=\(shouldRepeatVideoWhileLShape)")
            finishLShapeAndAdvanceToNext()
        }
    }

    /// ±1s tolerance when comparing video length (and N× loops) to L-shape hold.
    private static let lShapeDurationBufferSeconds: Double = 1.0

    /// Scale only when video is longer than L-shape (no repetition). Never scale after repeats.
    private func shouldScaleAfterLShapeHold(companionDuration: Int) -> Bool {
        let buffer = Self.lShapeDurationBufferSeconds
        let C = Double(companionDuration)
        let V = measuredMainVideoDuration ?? measuredMainVideoDurationSeconds()
        let remaining = remainingMainVideoSeconds() ?? 0

        // Repeating (or would repeat): stop at L-shape duration — never scale.
        if shouldRepeatVideoWhileLShape { return false }
        if let V, V < (C - buffer) { return false }

        // Equal / within ±1s (incl. exact loop fill) → next, no scale.
        if durationsWithinOneSecondBuffer(videoSeconds: V, companionDuration: companionDuration) {
            return false
        }

        // Only scale when video is clearly longer than the hold and playhead still has time.
        guard let V, V > (C + buffer) else { return false }
        return remaining > buffer
    }

    /// True when video and L-shape are within 1s, or N video loops fill the hold within 1s.
    private func durationsWithinOneSecondBuffer(videoSeconds: Double?, companionDuration: Int) -> Bool {
        let C = Double(companionDuration)
        let buffer = Self.lShapeDurationBufferSeconds
        guard let V = videoSeconds, V > 0 else {
            return (remainingMainVideoSeconds() ?? 0) <= buffer
        }
        if abs(V - C) <= buffer { return true }
        guard V < C else { return false }

        let remainder = C.truncatingRemainder(dividingBy: V)
        if remainder <= buffer || abs(remainder - V) <= buffer { return true }

        let loops = ceil(C / V)
        let covered = loops * V
        return abs(covered - C) <= buffer
    }

    /// Seconds still left on the current main video playhead (0 if ended / unknown).
    private func remainingMainVideoSeconds() -> Double? {
        guard let item = activePlayer?.currentItem else { return nil }
        let cur = CMTimeGetSeconds(item.currentTime())
        var dur = CMTimeGetSeconds(item.duration)
        if !dur.isFinite || dur <= 0 {
            dur = CMTimeGetSeconds(item.asset.duration)
        }
        if (!dur.isFinite || dur <= 0), let measured = measuredMainVideoDuration {
            dur = measured
        }
        guard cur.isFinite, dur.isFinite, dur > 0 else { return nil }
        return max(0, dur - cur)
    }

    /// Tear down L-shape + video and move to the next playlist group (no fullscreen scale).
    private func finishLShapeAndAdvanceToNext() {
        guard !isFinishingLShapeGroup else { return }
        isFinishingLShapeGroup = true

        timer?.invalidate()
        timer = nil
        shouldRepeatVideoWhileLShape = false
        lShapeCompanionDurationSeconds = nil
        lShapeHoldStartedAt = nil
        showsLShapeCompanions = false
        animateLShapeLayoutChange = false
        isMainSlotLoading = false
        showWhiteMainSlot = false
        videoEndEpoch &+= 1

        if let video = currentGroup?.ii.first(where: { $0.isVideoType && $0.hasMinimumPlayableFields }) {
            trackCompletion(for: video)
        }

        clearVideoObservers()
        activePlayer?.pause()
        activePlayer = nil
        activeVideoAd = nil
        transitionToNextItem()
    }

    /// Loop video only when it is more than 1s shorter than the L-shape hold.
    private func updateShouldRepeatVideoForLShape(companionDuration: Int) {
        let C = Double(companionDuration)
        let buffer = Self.lShapeDurationBufferSeconds
        if let videoSeconds = measuredMainVideoDuration ?? measuredMainVideoDurationSeconds() {
            measuredMainVideoDuration = videoSeconds
            shouldRepeatVideoWhileLShape = videoSeconds < (C - buffer)
            if shouldRepeatVideoWhileLShape {
                print("🔁 Measured video \(String(format: "%.2f", videoSeconds))s < L-shape \(companionDuration)s − \(buffer)s — will repeat until hold ends")
            } else if abs(videoSeconds - C) <= buffer {
                print("▶️ Measured video \(String(format: "%.2f", videoSeconds))s within ±\(buffer)s of L-shape \(companionDuration)s — next item at hold end (no scale)")
            } else {
                print("▶️ Measured video \(String(format: "%.2f", videoSeconds))s vs L-shape \(companionDuration)s — scale only if leftover > \(buffer)s")
            }
        } else {
            shouldRepeatVideoWhileLShape = true
            print("📏 Video duration not ready yet — will measure at readyToPlay")
        }
    }

    /// Duration from the playing item / asset (actual media), not the quest API field.
    private func measuredMainVideoDurationSeconds() -> Double? {
        guard let item = activePlayer?.currentItem else { return nil }
        let candidates = [item.duration, item.asset.duration]
        for d in candidates {
            guard d.isNumeric, !d.isIndefinite else { continue }
            let secs = CMTimeGetSeconds(d)
            if secs.isFinite, secs > 0 { return secs }
        }
        return nil
    }

    /// Always log the exact measured media duration (and quest API duration when present).
    private func printExactVideoDuration(for ad: AdItemModel) {
        let apiDuration = ad.duration.map { "\($0)" } ?? "nil"
        if let secs = measuredMainVideoDurationSeconds() {
            measuredMainVideoDuration = secs
            print("📏 Exact video duration: \(secs)s (api duration: \(apiDuration)s) item=\(ad.itemid.isEmpty ? ad.itemurl : ad.itemid)")
            return
        }
        guard let asset = activePlayer?.currentItem?.asset else {
            print("📏 Exact video duration: unavailable (api duration: \(apiDuration)s)")
            return
        }
        Task { @MainActor in
            do {
                let duration = try await asset.load(.duration)
                let secs = CMTimeGetSeconds(duration)
                if secs.isFinite, secs > 0 {
                    self.measuredMainVideoDuration = secs
                    print("📏 Exact video duration: \(secs)s (api duration: \(apiDuration)s) item=\(ad.itemid.isEmpty ? ad.itemurl : ad.itemid)")
                } else {
                    print("📏 Exact video duration: invalid \(secs) (api duration: \(apiDuration)s)")
                }
            } catch {
                print("📏 Exact video duration: load failed — \(error.localizedDescription) (api duration: \(apiDuration)s)")
            }
        }
    }

    /// Async load when player duration is still indefinite (common right after `AVPlayer(url:)`).
    private func measureAndApplyVideoDurationForLShape() {
        guard let companionDuration = lShapeCompanionDurationSeconds else { return }
        if let secs = measuredMainVideoDuration ?? measuredMainVideoDurationSeconds() {
            measuredMainVideoDuration = secs
            updateShouldRepeatVideoForLShape(companionDuration: companionDuration)
            return
        }
        guard let asset = activePlayer?.currentItem?.asset else { return }
        Task { @MainActor in
            do {
                let duration = try await asset.load(.duration)
                let secs = CMTimeGetSeconds(duration)
                guard secs.isFinite, secs > 0 else { return }
                guard self.lShapeCompanionDurationSeconds == companionDuration else { return }
                self.measuredMainVideoDuration = secs
                self.updateShouldRepeatVideoForLShape(companionDuration: companionDuration)
            } catch {
                print("⚠️ Could not measure video duration: \(error.localizedDescription)")
            }
        }
    }

    /// Main video/image failed — white in main slot and hold for L-shape (or group) duration, then advance.
    func skipCorruptMainContent() {
        handleCorruptMainContent()
    }

    /// Main creative failed at runtime.
    /// L-shape + healthy companions → branded fallback in main for companion duration.
    /// L-shape + any corrupt companion → skip.
    /// Single-item → branded fallback fullscreen for duration.
    func handleCorruptMainContent() {
        guard !isHandlingCorruptMain else { return }
        isHandlingCorruptMain = true

        clearVideoObservers()
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        activePlayer = nil
        showWhiteMainSlot = true
        isMainSlotLoading = false
        animateLShapeLayoutChange = false

        let group = currentGroup
        let companions = group?.lShapeCompanions ?? []
        let isLShape = (group?.ii.count ?? 0) >= 2

        guard isLShape else {
            showsLShapeCompanions = false
            print("🖼️ Main corrupt — branded fallback fullscreen for group duration")
            consecutiveCorruptSkips = 0
            startGroupTimer()
            isHandlingCorruptMain = false
            return
        }

        showsLShapeCompanions = false
        Task {
            await self.prefetchCompanions(companions)
            guard currentGroup?.sequence == group?.sequence else {
                self.isHandlingCorruptMain = false
                return
            }
            if companions.contains(where: { self.isUnusableCompanion($0) }) {
                print("⏭️ Corrupt video + broken L-shape — skipping group")
                self.skipEntireCorruptGroup()
                return
            }
            self.showsLShapeCompanions = true
            self.showWhiteMainSlot = true
            print("🖼️ Main video corrupt — branded fallback + L-shape for companion duration")
            self.consecutiveCorruptSkips = 0
            self.scheduleWhiteMainHoldThenAdvance(companions: companions)
            self.isHandlingCorruptMain = false
        }
    }

    /// Hold branded/fallback main + companions for max companion duration, then advance.
    func scheduleWhiteMainHoldThenAdvance(companions: [AdItemModel]) {
        timer?.invalidate()
        timer = nil
        let fromCompanions = companions.compactMap(\.duration).filter { $0 > 0 }.max()
        let fromGroup = currentGroup?.ii.compactMap(\.duration).filter { $0 > 0 }.max()
        let duration = fromCompanions ?? fromGroup ?? 20
        print("🖼️ Fallback main hold for \(duration)s (L-shape duration), then next")
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(duration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let group = self.currentGroup {
                    for ad in group.ii where ad.assettype.lowercased() == "image" {
                        self.trackImageViewComplete(for: ad, duration: duration)
                    }
                }
                self.timer?.invalidate()
                self.timer = nil
                self.transitionToNextItem()
            }
        }
    }

    func clearVideoObservers() {
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
            self.videoEndObserver = nil
        }
        if let videoFailedObserver {
            NotificationCenter.default.removeObserver(videoFailedObserver)
            self.videoFailedObserver = nil
        }
    }

    func playVideo(_ ad: AdItemModel) {
        clearVideoObservers()
        activeVideoAd = ad
        measuredMainVideoDuration = nil
        videoEndEpoch &+= 1
        let endEpoch = videoEndEpoch

        let cachedURL = localURLs[ad.itemurl]
        let remoteURL = ad.mediaURL
        
        guard let playURL = cachedURL ?? remoteURL else {
            print("❌ Invalid URL:", ad.itemurl)
            skipCorruptMainContent()
            return
        }
        
        // Log which URL we're using
        if cachedURL != nil {
            print("▶️ Playing from cache: \(playURL.lastPathComponent)")
        } else {
            print("⚠️ Playing from REMOTE (not cached): \(ad.itemurl)")
        }

        let player = AVPlayer(url: playURL)
        activePlayer = player
        player.play()
        
        // Clear Now Playing info to suppress system UI
        MediaSessionHelper.shared.clearNowPlayingInfo()

        let item = player.currentItem
        playerItemStatusObservation = item?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    let message = item.error?.localizedDescription ?? "unknown"
                    print("❌ Main video failed to load: \(message)")
                    self.skipCorruptMainContent()
                } else if item.status == .readyToPlay {
                    // Swap loader for real video frames.
                    self.isMainSlotLoading = false
                    self.showWhiteMainSlot = false
                    self.trackImpression(for: ad)
                    self.printExactVideoDuration(for: ad)
                    // File duration is reliable once ready — decide L-shape video repeat from it.
                    self.measureAndApplyVideoDurationForLShape()
                }
            }
        }

        videoFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                print("❌ Main video failed during playback: \(err?.localizedDescription ?? "unknown")")
                self?.skipCorruptMainContent()
            }
        }

        installVideoEndObserver(for: ad, epoch: endEpoch)
    }

    /// Bind / re-bind end observer. `epoch` ignores stale ends after L-scale or advance.
    private func installVideoEndObserver(for ad: AdItemModel?, epoch: UInt64) {
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
            self.videoEndObserver = nil
        }
        guard let ad,
              let item = activePlayer?.currentItem else { return }

        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.videoEndEpoch == epoch else {
                    print("📐 Ignoring stale video-end (epoch \(epoch) ≠ \(self.videoEndEpoch))")
                    return
                }
                guard !self.isFinishingLShapeGroup else { return }

                // Still in L-shape: video hit a natural end — never scale; restart or advance.
                if self.showsLShapeCompanions {
                    if self.shouldRepeatVideoWhileLShape, let player = self.activePlayer {
                        let holdFilled: Bool = {
                            guard let C = self.lShapeCompanionDurationSeconds,
                                  let started = self.lShapeHoldStartedAt else { return false }
                            return Date().timeIntervalSince(started) + Self.lShapeDurationBufferSeconds >= Double(C)
                        }()
                        if !holdFilled {
                            print("🔁 Restarting video to fill L-shape image duration")
                            player.seek(to: .zero)
                            player.play()
                            return
                        }
                    }
                    // At end during L-shape (equal / filled repeats) — never scale.
                    print("📐 Video ended during L-shape — next item (no scale)")
                    if let C = self.lShapeCompanionDurationSeconds, let group = self.currentGroup {
                        for imageAd in group.ii where imageAd.assettype.lowercased() == "image" {
                            guard !self.isUnusableCompanion(imageAd) else { continue }
                            self.trackImageViewComplete(for: imageAd, duration: C)
                        }
                    }
                    self.finishLShapeAndAdvanceToNext()
                    return
                }

                // After L-shape removal (scaled fullscreen): finish when video ends.
                self.timer?.invalidate()
                self.timer = nil
                self.clearVideoObservers()
                self.trackCompletion(for: ad)
                self.transitionToNextItem()
            }
        }
    }
    
    // MARK: - Impression Tracking

    /// Only fire trackers for creatives that are playable and (for images) loaded into cache.
    func canFireTracker(for ad: AdItemModel) -> Bool {
        guard ad.hasMinimumPlayableFields else { return false }
        if ad.isImageType {
            guard let image = imageCache[ad.itemurl], image.size.width > 1, image.size.height > 1 else {
                return false
            }
            return true
        }
        if ad.isVideoType {
            return activePlayer != nil && !showWhiteMainSlot && !isMainSlotLoading
        }
        return false
    }

    private func impressionKey(for ad: AdItemModel) -> String {
        let id = ad.itemid.isEmpty ? ad.itemurl : ad.itemid
        return "\(currentGroup?.sequence ?? 0)|\(id)"
    }

    /// Fires `trackerlist` once per creative per group when it is actually shown.
    func trackImpression(for ad: AdItemModel) {
        guard !disablePreloadingAndValidation else { return }
        guard canFireTracker(for: ad) else {
            print("🚫 Skip impression tracker — corrupt/unusable creative")
            return
        }
        let key = impressionKey(for: ad)
        guard !firedImpressionKeys.contains(key) else {
            print("🚫 Skip impression tracker — already fired for this creative in group")
            return
        }
        firedImpressionKeys.insert(key)

        if let trackers = ad.trackerlist, !trackers.isEmpty {
            print("📡 Impression tracker for itemid=\(ad.itemid.isEmpty ? "(url)" : ad.itemid) urls=\(trackers.count)")
            TrackerService.shared.fire(urls: trackers)
        }
        let itemId = String(ad.itemid.prefix(120))
        SentryService.shared.track(
            SentryAnalyticsEvent.adImpression,
            attributes: [
                "asset_type": String(ad.assettype.prefix(32)),
                "item_id": itemId,
                "sequence": "\(currentGroup?.sequence ?? 0)"
            ],
            sampleRate: 0.2
        )
    }

    /// View/playback finished — do not re-fire impression `trackerlist` (those are one-shot pixels).
    func trackCompletion(for ad: AdItemModel) {
        guard !disablePreloadingAndValidation else { return }
        guard canFireTracker(for: ad) else { return }
        print("✅ Creative completed itemid=\(ad.itemid.isEmpty ? "(url)" : ad.itemid) (no re-fire of impression trackers)")
    }

    /// Image dwell finished — do not re-fire impression `trackerlist`.
    func trackImageViewComplete(for ad: AdItemModel, duration: Int) {
        guard !disablePreloadingAndValidation else { return }
        guard canFireTracker(for: ad) else { return }
        print("✅ Image view complete itemid=\(ad.itemid.isEmpty ? "(url)" : ad.itemid) duration=\(duration)s (no re-fire of impression trackers)")
    }

    /// Load image from local disk/remote and cache it in memory.
    /// - Parameter timeout: remote fetch timeout (companions use a short value to fail fast).
    func loadImage(for ad: AdItemModel, timeout: TimeInterval = 30) async {
        if imageCache[ad.itemurl] != nil { return }

        // Prefer on-disk cache (instant).
        if let cached = localURLs[ad.itemurl] {
            do {
                let data = try Data(contentsOf: cached)
                if let image = UIImage(data: data), image.size.width > 1 {
                    storeImage(image, forKey: ad.itemurl)
                    print("🖼️ Cached image (disk):", ad.itemurl)
                }
            } catch {
                print("❌ Image disk load failed:", ad.itemurl, error.localizedDescription)
            }
            return
        }

        guard let remoteURL = ad.mediaURL else {
            print("❌ Image load skipped — invalid URL:", ad.itemurl)
            return
        }

        guard NetworkMonitor.shared.canMakeNetworkCalls else {
            print("📵 Image network load skipped — no internet:", ad.itemurl)
            return
        }

        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = timeout
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("❌ Image HTTP \(http.statusCode):", ad.itemurl)
                return
            }
            if let image = UIImage(data: data), image.size.width > 1 {
                storeImage(image, forKey: ad.itemurl)
                print("🖼️ Cached image (network):", ad.itemurl)
            } else {
                print("❌ Image decode failed (bytes=\(data.count)):", ad.itemurl)
            }
        } catch {
            print("❌ Image load failed:", ad.itemurl, error.localizedDescription)
        }
    }

    /// Image-group dwell time: use quest `duration` when present, else 20s.
    func startGroupTimer() {
        timer?.invalidate()
        let defaultDuration = 20
        let fromAPI = currentGroup?.ii
            .filter { $0.assettype.lowercased() == "image" }
            .compactMap(\.duration)
            .filter { $0 > 0 }
        let duration = fromAPI?.max() ?? defaultDuration
        print("🖼️ Image group duration: \(duration)s\(fromAPI?.isEmpty == false ? " (from API)" : " (default)")")
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

        playCurrentGroup()
    }
}

// MARK: - Sync helpers
private extension AdPlayerViewModel {
    func startAutoSync(screenId: String) {
        guard syncTimer == nil else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: repeatInTime, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncAds(with: screenId)
            }
        }
    }

    func syncAds(with screenId: String) {
        guard NetworkMonitor.shared.canMakeNetworkCalls else {
            print("📵 Quest sync skipped — no internet")
            return
        }
        reqNum += 1
        print("🌐 Running periodic API sync... with reqNum: \(reqNum)")

        Task {
            do {
                let response = try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                print("🔄 Sync data fetched: \(response.groupedAds.count) groups status=\(response.status ?? "nil")")

                if response.isNoDataFound {
                    print("⏳ Quest sync NO_DATA_FOUND — waiting for content")
                    PlaylistCacheService.shared.clearCache()
                    enterWaitingForPlayableContent()
                    NotificationCenter.default.post(
                        name: .questPlaylistApplied,
                        object: nil,
                        userInfo: ["groupedAds": [AdSequenceGroup]()]
                    )
                    consecutiveSyncFailures = 0
                    isUsingFallbackContent = false
                    HeartbeatAPI.shared.updateLastSyncTime()
                    return
                }
                
                // Only replace playlist + purge cache when ≥1 playable item arrives.
                let playablePending = response.groupedAds.displayableGroups()
                if !playablePending.isEmpty {
                    pendingGroups = playablePending
                    isPendingDownloadComplete = false
                    PlaylistCacheService.shared.savePlaylist(playablePending)
                    await startBackgroundDownload()
                } else {
                    print("ℹ️ Quest sync has no playable image/video — keeping current playlist and cache")
                    // If we have nothing to play at all, show waiting (still do not wipe disk).
                    if !hasActivePlayablePlaylist {
                        enterWaitingForPlayableContent()
                    }
                }
                
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
    
    /// Download new assets in background, then apply the playlist and purge obsolete cache.
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
        print("✅ Background download complete — applying playlist and removing obsolete cache")

        // Successful playable update: switch now (don't keep looping unmatched old video/images).
        await applyPendingPlaylistSafely()
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
        SentryService.shared.capture(error: error, tags: ["layer": "playback", "reason": "sync_fallback"])
    }

    func applyPendingPlaylistSafely() async {
        guard !pendingGroups.isEmpty else { return }

        print("📥 Applying NEW playlist (downloads already complete)…")

        let newGroups = await filterUnplayableAds(newAds: pendingGroups)
        pendingGroups.removeAll()
        isPendingDownloadComplete = false

        guard !newGroups.isEmpty else {
            print("⚠️ Pending playlist filtered to empty — keeping current playlist and cache")
            return
        }

        // STEP 1 — Stop current playback before swapping creatives
        clearVideoObservers()
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        activePlayer = nil

        // STEP 2 — Align disk + memory to ONLY this successful playlist (video-only / images-only / mixed)
        localURLs.removeAll()
        imageCache.removeAll()
        retainOnlyCurrentPlaylist(newGroups)

        // STEP 3 — Rebuild localURLs using files on disk for new playlist
        print("🔍 Rebuilding localURLs for \(newGroups.flatMap { $0.ii }.count) ads...")
        var foundCount = 0
        var missingCount = 0
        
        for group in newGroups {
            for ad in group.ii {
                // Use lowercased filename to match how downloadAsset saves files
                let fileName = ad.mediaURL?.lastPathComponent.lowercased() ?? ""
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

        // STEP 4 — Apply playlist
        isWaitingForPlayableContent = false
        showsLShapeCompanions = false
        groupedAds = newGroups
        currentIndex = 0

        // STEP 5 — Decode ALL images into memory (current playlist only)
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

        // Keep RootView waiting overlay in sync (it watches AdPlaylistViewModel.groupedAds).
        NotificationCenter.default.post(
            name: .questPlaylistApplied,
            object: nil,
            userInfo: ["groupedAds": newGroups]
        )
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
            group.ii.compactMap { $0.mediaURL?.lastPathComponent.lowercased() }
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


