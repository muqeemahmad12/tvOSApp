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
                groupedAds = groups
                ads = groups.flatMap { $0.ii }
                isUsingCachedPlaylist = false
                
                // Cache the playlist for offline use
                cacheService.savePlaylist(groups)
            } catch {
                let appError = AppError.from(error)
                errorMessage = appError.localizedDescription
                print("❌ Playlist API Failed:", appError)
                
                // Fall back to cached playlist if API fails
                if groupedAds.isEmpty, let cached = cacheService.loadCachedPlaylist() {
                    groupedAds = cached
                    ads = cached.flatMap { $0.ii }
                    isUsingCachedPlaylist = true
                    print("📂 API failed - using cached playlist as fallback")
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
