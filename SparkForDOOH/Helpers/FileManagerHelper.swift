//
//  FileManagerHelper.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 04/11/25.
//

import Foundation

final class FileManagerHelper {
    static let shared = FileManagerHelper()
    private let fileManager = FileManager.default
    
    /// Directories to preserve when clearing caches.
    /// - io.sentry: Sentry crash reports
    /// - AdsCache: Downloaded ad assets for playback
    /// - PlaylistCache: Cached playlist structure for offline relaunch
    /// - com.doceree.sparkdooh.tvos: URLSession/system SQLite cache (deleting while in use causes libsqlite3 errors)
    private let protectedDirectoryNames: Set<String> = [
        "io.sentry",
        "AdsCache",
        "PlaylistCache",
        "com.doceree.sparkdooh.tvos"
    ]

    // MARK: - Clear Files
    private func clearDirectory(_ directory: FileManager.SearchPathDirectory) {
        guard let dirURL = fileManager.urls(for: directory, in: .userDomainMask).first else { return }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            for url in fileURLs {
                // Skip protected directories (e.g. Sentry crash data)
                if protectedDirectoryNames.contains(url.lastPathComponent) {
                    print("⏭️ Skipping protected directory: \(url.lastPathComponent)")
                    continue
                }
                try fileManager.removeItem(at: url)
            }
            print("✅ Cleared files in \(directory)")
        } catch {
            print("❌ Error clearing directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Clear Both
    func clearAppStorage() {
        print("🧹 Clearing all app storage...")
        clearDirectory(.documentDirectory)
        clearDirectory(.cachesDirectory)
        clearTemporaryDirectory()
        print("✅ All app storage cleared.")
    }
    
    // MARK: - Clear Temporary
    private func clearTemporaryDirectory() {
        let tmpURL = fileManager.temporaryDirectory
        do {
            let tmpFiles = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
            for file in tmpFiles {
                try fileManager.removeItem(at: file)
            }
            print("✅ Cleared temporary directory")
        } catch {
            print("❌ Error clearing temp: \(error.localizedDescription)")
        }
    }
}
