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
    
    /// Save playlist to disk
    func savePlaylist(_ groups: [AdSequenceGroup]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(groups)
            try data.write(to: playlistFileURL)
            
            // Also save timestamp
            UserDefaults.standard.set(Date(), forKey: "lastPlaylistCacheTime")
            
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
    
    /// Check if cached playlist exists
    var hasCachedPlaylist: Bool {
        fileManager.fileExists(atPath: playlistFileURL.path)
    }
    
    /// Get the timestamp when playlist was last cached
    var lastCacheTime: Date? {
        UserDefaults.standard.object(forKey: "lastPlaylistCacheTime") as? Date
    }
    
    /// Check if cache is stale (older than specified hours)
    func isCacheStale(hours: Int = 24) -> Bool {
        guard let lastCache = lastCacheTime else { return true }
        let staleThreshold = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        return lastCache < staleThreshold
    }
    
    /// Clear cached playlist
    func clearCache() {
        try? fileManager.removeItem(at: playlistFileURL)
        UserDefaults.standard.removeObject(forKey: "lastPlaylistCacheTime")
        print("🗑️ Playlist cache cleared")
    }
}

