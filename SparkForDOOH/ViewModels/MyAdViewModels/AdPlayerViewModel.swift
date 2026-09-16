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
    fileprivate var isSkippingCorruptMain = false
    /// Counts corrupt skips in one full playlist pass; if all fail → waiting (keep disk cache).
    fileprivate var consecutiveCorruptSkips = 0
    
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
                    showsLShapeCompanions = true
                    scheduleLShapeCollapseIfNeeded(images: images)
                } else if !hasVideo {
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
            group.ii
                .filter { $0.hasMinimumPlayableFields }
                .compactMap { URL(string: $0.itemurl)?.lastPathComponent.lowercased() }
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
                guard URL(string: ad.itemurl) != nil || localURLs[ad.itemurl] != nil else {
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
        consecutiveCorruptSkips = 0
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

        // Play video whenever a playable one exists.
        // L-shape companions show first; after their duration the video scales fullscreen.
        // Unplayable companions (incl. zip typed as video) stay as white — never reuse another image.
        if let video {
            trackImpression(for: video)
            showsLShapeCompanions = !companions.isEmpty
            for ad in companions where ad.hasMinimumPlayableFields {
                trackImpression(for: ad)
            }
            Task {
                for ad in companions where ad.hasMinimumPlayableFields {
                    await loadImage(for: ad)
                }
                guard currentGroup?.sequence == group.sequence else { return }
                let failed = companions.filter {
                    $0.hasMinimumPlayableFields && self.imageCache[$0.itemurl] == nil
                }
                if !failed.isEmpty {
                    print("⬜ \(failed.count) L-shape companion(s) failed — showing white in place")
                }
            }
            playVideo(video)
            if !companions.isEmpty {
                scheduleLShapeCollapseIfNeeded(images: companions)
            }
            return
        }

        // Unplayable main video (e.g. zip) + companions → white main, keep L-shape slots.
        if hasUnplayableVideoSlot && !companions.isEmpty {
            print("⬜ Unplayable main video — white in main slot, keeping L-shape companions")
            showsLShapeCompanions = true
            activePlayer = nil
            for ad in companions where ad.hasMinimumPlayableFields {
                trackImpression(for: ad)
            }
            Task {
                for ad in companions where ad.hasMinimumPlayableFields {
                    await loadImage(for: ad)
                }
                guard currentGroup?.sequence == group.sequence else { return }
                startGroupTimer()
            }
            return
        }

        // Image-only: load first; if main (lead) image is corrupt/unplayable, white main (multi)
        // or skip group (single) — never stretch companions into the main slot.
        showsLShapeCompanions = false
        let images = companions
        for ad in images where ad.hasMinimumPlayableFields {
            trackImpression(for: ad)
        }
        Task {
            for ad in images where ad.hasMinimumPlayableFields {
                await loadImage(for: ad)
            }
            guard currentGroup?.sequence == group.sequence else { return }
            if let main = images.first {
                let mainPlayable = main.hasMinimumPlayableFields && imageCache[main.itemurl] != nil
                if !mainPlayable {
                    if images.count >= 2 {
                        print("⬜ Main image unplayable — white in place (keeping other slots)")
                        startGroupTimer()
                        return
                    }
                    print("⏭️ Main image corrupt/unreadable — skipping group \(group.sequence)")
                    skipCorruptMainContent()
                    return
                }
            }
            startGroupTimer()
        }
    }

    /// Keep L-shape for companion `duration`, then hide banners and scale video to fullscreen.
    /// Only runs while main video is healthy; corrupt main skips the group instead.
    func scheduleLShapeCollapseIfNeeded(images: [AdItemModel]) {
        timer?.invalidate()
        timer = nil
        guard !images.isEmpty else { return }
        guard let companionDuration = images.compactMap(\.duration).filter({ $0 > 0 }).max() else {
            print("📐 L-shape for full video (no companion duration from API)")
            return
        }
        print("📐 L-shape for \(companionDuration)s, then scale video fullscreen")
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(companionDuration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // If player already failed/cleared, do not scale companions.
                guard self.activePlayer != nil else { return }
                print("📐 L-shape duration ended — scaling video fullscreen")
                if let group = self.currentGroup {
                    for ad in group.ii where ad.assettype.lowercased() == "image" {
                        self.trackImageViewComplete(for: ad, duration: companionDuration)
                    }
                }
                self.showsLShapeCompanions = false
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    /// Main video/image failed — advance without expanding L-shape companions.
    /// If every item in the playlist fails, go to waiting and keep disk cache.
    func skipCorruptMainContent() {
        guard !isSkippingCorruptMain else { return }
        isSkippingCorruptMain = true
        print("⏭️ Skipping item — main creative corrupt/invalid (L-shape will not be scaled)")
        clearVideoObservers()
        timer?.invalidate()
        timer = nil
        activePlayer?.pause()
        activePlayer = nil
        showsLShapeCompanions = false

        consecutiveCorruptSkips += 1
        let total = max(groupedAds.count, 1)
        if consecutiveCorruptSkips >= total {
            print("⏳ All \(total) playlist item(s) unplayable at runtime — waiting (disk cache kept)")
            isSkippingCorruptMain = false
            enterWaitingForPlayableContent()
            return
        }

        transitionToNextItem()
        isSkippingCorruptMain = false
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

        let cachedURL = localURLs[ad.itemurl]
        let remoteURL = URL(string: ad.itemurl)
        
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

        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.timer?.invalidate()
                self?.timer = nil
                self?.clearVideoObservers()
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
        reqNum += 1
        print("🌐 Running periodic API sync... with reqNum: \(reqNum)")

        Task {
            do {
                let response = try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                print("🔄 Sync data fetched: \(response.groupedAds.count) groups")
                
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


