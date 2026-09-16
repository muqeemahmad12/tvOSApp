//
//  PlaylistCacheService.swift
//  SparkForDOOH
//
//  Persists playlist structure to disk for offline relaunch support.
//

import Foundation

/// Service to cache and retrieve playlist structure (sequence order, metadata).
/// Ensures the app can resume playback with correct order even after relaunch.
final class PlaylistCacheService {
    static let shared = PlaylistCacheService()
    
    private let fileManager = FileManager.default
    private let playlistFileName = "cached_playlist.json"
    
    private var cacheDirectory: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PlaylistCache")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var playlistFileURL: URL {
        cacheDirectory.appendingPathComponent(playlistFileName)
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save playlist to disk. Empty lists are ignored so a blank API response
    /// cannot overwrite a previously good offline cache.
    func savePlaylist(_ groups: [AdSequenceGroup]) {
        guard !groups.isEmpty else {
            print("ℹ️ Skipping playlist cache save — empty groups")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(groups)
            try data.write(to: playlistFileURL)
            
            print("💾 Playlist cached: \(groups.count) groups saved to disk")
        } catch {
            print("❌ Failed to cache playlist: \(error.localizedDescription)")
        }
    }
    
    /// Load playlist from disk
    func loadCachedPlaylist() -> [AdSequenceGroup]? {
        guard fileManager.fileExists(atPath: playlistFileURL.path) else {
            print("📂 No cached playlist found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: playlistFileURL)
            let decoder = JSONDecoder()
            let groups = try decoder.decode([AdSequenceGroup].self, from: data)
            
            print("📂 Loaded cached playlist: \(groups.count) groups")
            return groups
        } catch {
            print("❌ Failed to load cached playlist: \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove saved playlist JSON (e.g. on screen deactivation).
    func clearCache() {
        try? fileManager.removeItem(at: playlistFileURL)
        print("🗑️ Playlist cache cleared")
    }
}

