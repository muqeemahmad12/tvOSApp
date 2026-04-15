//
//  AdPlaylistViewModel.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import Combine

/// Loads and exposes the current ad playlist (grouped ads) for a given screen,
/// handling loading state, basic retries, caching, and user-friendly error messages.
@MainActor
final class AdPlaylistViewModel: ObservableObject {
    @Published var ads: [AdItemModel] = []                // Flattened list (optional)
    @Published var groupedAds: [AdSequenceGroup] = []     // Grouped list (1–3 per sequence)
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isUsingCachedPlaylist = false          // True if using offline cache
    
    private let cacheService = PlaylistCacheService.shared

    init() {
        // Always hydrate from cache immediately so offline launches can play.
        loadCachedPlaylistIfAvailable()
    }
    
    /// Load cached playlist immediately on init (for fast launch)
    func loadCachedPlaylistIfAvailable() {
        if let cached = cacheService.loadCachedPlaylist(), !cached.isEmpty {
            groupedAds = cached
            ads = cached.flatMap { $0.ii }
            isUsingCachedPlaylist = true
            print("📂 Using cached playlist for immediate playback")
        }
    }

    func fetchAds(screenId: String, reqNum: Int) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await AdPlaylistViewModel.fetchWithRetry(
                    attempts: 3,
                    delaySeconds: 3
                ) {
                    try await APIService.shared.fetchItemSeqInfo(screenId: screenId,
                                                                            reqNum: reqNum)
                }

                let groups = response.groupedAds
                if groups.isEmpty {
                    // If API returns empty, keep using cache if available.
                    if let cached = cacheService.loadCachedPlaylist(), !cached.isEmpty {
                        groupedAds = cached
                        ads = cached.flatMap { $0.ii }
                        isUsingCachedPlaylist = true
                        print("📂 Empty API playlist - continuing with cached content")
                        SentryService.shared.track(SentryAnalyticsEvent.playlistEmpty, attributes: ["used_cache": "true"])
                    } else {
                        groupedAds = []
                        ads = []
                        isUsingCachedPlaylist = false
                        print("⚠️ Empty API playlist and no cache available")
                        SentryService.shared.track(SentryAnalyticsEvent.playlistEmpty, attributes: ["used_cache": "false"])
                    }
                    SentryService.shared.breadcrumb(category: "playlist", message: "empty_response", data: [:])
                } else {
                    groupedAds = groups
                    ads = groups.flatMap { $0.ii }
                    isUsingCachedPlaylist = false
                    let itemCount = ads.count
                    SentryService.shared.track(
                        SentryAnalyticsEvent.playlistLoaded,
                        attributes: ["group_count": "\(groups.count)", "item_count": "\(itemCount)"]
                    )
                    SentryService.shared.breadcrumb(
                        category: "playlist",
                        message: "fetch_success",
                        data: ["groups": "\(groups.count)", "items": "\(itemCount)"]
                    )
                    // Cache the playlist for offline use
                    cacheService.savePlaylist(groups)
                }
            } catch {
                let appError = AppError.from(error)
                errorMessage = appError.localizedDescription
                print("❌ Playlist API Failed:", appError)
                let errSummary = String(describing: appError).prefix(200)
                SentryService.shared.track(SentryAnalyticsEvent.playlistFetchFailed, attributes: ["error": String(errSummary)])
                SentryService.shared.breadcrumb(
                    category: "playlist",
                    message: "fetch_error",
                    data: ["error": String(errSummary)]
                )

                // Fall back to cached playlist if API fails
                if groupedAds.isEmpty, let cached = cacheService.loadCachedPlaylist() {
                    groupedAds = cached
                    ads = cached.flatMap { $0.ii }
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
