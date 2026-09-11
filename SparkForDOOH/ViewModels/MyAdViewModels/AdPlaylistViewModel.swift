//
//  AdPlaylistViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import Combine

/// Loads and exposes the current ad playlist (grouped ads) for a given screen,
/// handling loading state, basic retries, and offline cache.
@MainActor
final class AdPlaylistViewModel: ObservableObject {
    @Published var groupedAds: [AdSequenceGroup] = []
    @Published var isLoading = false
    @Published var isUsingCachedPlaylist = false
    
    private let cacheService = PlaylistCacheService.shared
    private var questPlaylistObserver: NSObjectProtocol?

    init() {
        // Always hydrate from cache immediately so offline launches can play.
        loadCachedPlaylistIfAvailable()

        questPlaylistObserver = NotificationCenter.default.addObserver(
            forName: .questPlaylistApplied,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let groups = (notification.userInfo?["groupedAds"] as? [AdSequenceGroup]) ?? []
            Task { @MainActor in
                self?.applySyncedPlaylist(groups)
            }
        }
    }

    deinit {
        if let questPlaylistObserver {
            NotificationCenter.default.removeObserver(questPlaylistObserver)
        }
    }

    /// Update published playlist when player sync applies content (dismisses waiting screen).
    func applySyncedPlaylist(_ groups: [AdSequenceGroup]) {
        let playable = groups.displayableGroups()
        if playable == groupedAds { return }
        groupedAds = playable
        isUsingCachedPlaylist = false
        if playable.isEmpty {
            print("📂 Playlist VM cleared from sync — waiting for playable content")
        } else {
            print("📂 Playlist VM updated from sync — waiting screen can dismiss")
        }
    }
    
    /// Load cached playlist immediately on init (for fast launch)
    func loadCachedPlaylistIfAvailable() {
        if let cached = cacheService.loadCachedPlaylist()?.displayableGroups(), !cached.isEmpty {
            groupedAds = cached
            isUsingCachedPlaylist = true
            print("📂 Using cached playlist for immediate playback")
        }
    }

    func fetchAds(screenId: String, reqNum: Int) {
        // Offline: prefer cached playlist immediately — do not retry quest forever.
        if !NetworkMonitor.shared.isConnected {
            if groupedAds.isEmpty {
                loadCachedPlaylistIfAvailable()
            }
            if !groupedAds.isEmpty {
                print("📴 Offline — playing cached playlist (skipping quest fetch)")
                isLoading = false
                return
            }
            print("📴 Offline — no cached playlist available")
            isLoading = false
            return
        }

        isLoading = true

        Task {
            do {
                let response = try await AdPlaylistViewModel.fetchWithRetry(
                    attempts: 3,
                    delaySeconds: 3
                ) {
                    try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                }

                let groups = response.groupedAds.displayableGroups()
                if groups.isEmpty {
                    // No playable items yet — keep current / cached playlist unchanged (no wipe).
                    if groupedAds.isEmpty,
                       let cached = cacheService.loadCachedPlaylist()?.displayableGroups(),
                       !cached.isEmpty {
                        groupedAds = cached
                        isUsingCachedPlaylist = true
                        print("📂 Quest has no playable image/video — continuing with cached playlist")
                        SentryService.shared.track(SentryAnalyticsEvent.playlistEmpty, attributes: ["used_cache": "true", "reason": "no_playable_media"])
                    } else if !groupedAds.isEmpty {
                        print("ℹ️ Quest has no playable image/video — keeping current playlist")
                        SentryService.shared.track(SentryAnalyticsEvent.playlistEmpty, attributes: ["used_cache": "current", "reason": "no_playable_media"])
                    } else {
                        print("⚠️ Quest has no playable image/video and no cache — waiting for content")
                        SentryService.shared.track(SentryAnalyticsEvent.playlistEmpty, attributes: ["used_cache": "false", "reason": "no_playable_media"])
                    }
                    SentryService.shared.breadcrumb(category: "playlist", message: "empty_or_unplayable_response", data: [:])
                } else {
                    groupedAds = groups
                    isUsingCachedPlaylist = false
                    let itemCount = groups.flatMap(\.ii).count
                    SentryService.shared.track(
                        SentryAnalyticsEvent.playlistLoaded,
                        attributes: ["group_count": "\(groups.count)", "item_count": "\(itemCount)"]
                    )
                    SentryService.shared.breadcrumb(
                        category: "playlist",
                        message: "fetch_success",
                        data: ["groups": "\(groups.count)", "items": "\(itemCount)"]
                    )
                    // Only overwrite saved playlist when ≥1 playable item arrives
                    cacheService.savePlaylist(groups)
                }
            } catch {
                let appError = AppError.from(error)
                print("❌ Playlist API Failed:", appError)
                let errSummary = String(describing: appError).prefix(200)
                SentryService.shared.track(SentryAnalyticsEvent.playlistFetchFailed, attributes: ["error": String(errSummary)])
                SentryService.shared.breadcrumb(
                    category: "playlist",
                    message: "fetch_error",
                    data: ["error": String(errSummary)]
                )

                // Fall back to cached playlist if API fails
                if groupedAds.isEmpty, let cached = cacheService.loadCachedPlaylist()?.displayableGroups(), !cached.isEmpty {
                    groupedAds = cached
                    isUsingCachedPlaylist = true
                    print("📂 API failed - using cached playlist as fallback")
                    SentryService.shared.track(SentryAnalyticsEvent.playlistUsedCache)
                    SentryService.shared.breadcrumb(category: "playlist", message: "cache_fallback_after_error", data: [:])
                }
            }

            isLoading = false
        }
    }

    // MARK: - Retry helper

    private static func fetchWithRetry<T>(
        attempts: Int,
        delaySeconds: UInt64,
        task: @escaping () async throws -> T
    ) async throws -> T {
        var currentAttempt = 0
        var lastError: Error?

        while currentAttempt < attempts {
            currentAttempt += 1
            do {
                return try await task()
            } catch {
                lastError = error
                if currentAttempt < attempts {
                    let backoff = delaySeconds * UInt64(currentAttempt)
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                }
            }
        }

        throw lastError ?? AppError.unknown
    }
}
