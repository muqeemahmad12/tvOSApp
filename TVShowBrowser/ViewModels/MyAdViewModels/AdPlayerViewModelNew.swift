//
//  AdPlayerViewModelNew.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import Foundation
import AVKit
import SwiftUI

// MARK: - Player ViewModel
@MainActor
final class AdPlayerViewModelNew: ObservableObject {
    @Published var currentAd: AdItemModel?
    @Published var player: AVPlayer?
    @Published var isPreloading = false
    @Published var preloadProgress: Double = 0.0
    @Published var transitionOpacity: Double = 1.0

    private var ads: [AdItemModel] = []
    private var localURLs: [String: URL] = [:]
    private var currentIndex = 0
    private var timer: Timer?
    
    func startPlayback(with ads: [AdItemModel]) {
        // Filter out large assets (above 1920x1080)
        let validAds = ads
            .filter { !$0.isTooLarge }
            .sorted { $0.sequence < $1.sequence }

        guard !validAds.isEmpty else {
            print("⚠️ No valid ads found after filtering large assets.")
            return
        }

        self.ads = validAds
        preloadAllAssets()
        checkFileManager()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        player?.pause()
    }

    private func preloadAllAssets() {
        isPreloading = true
        preloadProgress = 0.0
        localURLs.removeAll()

        Task {
            let total = Double(ads.count)
            var completed = 0.0

            for ad in ads {
                guard !ad.isTooLarge else {
                    print("⏭️ Skipping large ad (\(ad.itemsize)) with URL: \(ad.itemurl)")
                    continue
                }

                if let url = await downloadAsset(ad.itemurl) {
                    localURLs[ad.itemid] = url
                }
                completed += 1
                preloadProgress = completed / total
            }

            isPreloading = false
            playCurrent()
        }
    }

    private func downloadAsset(_ urlString: String) async -> URL? {
        guard let remoteURL = URL(string: urlString) else { return nil }
        let fileName = remoteURL.lastPathComponent
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            try data.write(to: destination)
            return destination
        } catch {
            print("❌ Download failed: \(urlString) — \(error)")
            return nil
        }
    }
    
    func checkFileManager() {
        let fm = FileManager.default
        let paths = [
            ("Documents", fm.urls(for: .documentDirectory, in: .userDomainMask).first!),
            ("Caches", fm.urls(for: .cachesDirectory, in: .userDomainMask).first!),
            ("Temporary", fm.temporaryDirectory)
        ]
        
        for (name, path) in paths {
            print("🔍 Checking \(name): \(path.path)")
            var totalSize: UInt64 = 0
            
            if let files = try? fm.contentsOfDirectory(at: path, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) {
                if files.isEmpty {
                    print("  ⚠️ No files here")
                } else {
                    for file in files {
                        do {
                            let attributes = try fm.attributesOfItem(atPath: file.path)
                            let fileSize = attributes[.size] as? UInt64 ?? 0
                            totalSize += fileSize
                            
                            // Print per-file size in KB or MB
                            let sizeKB = Double(fileSize) / 1024.0
                            let sizeString = sizeKB > 1024 ? String(format: "%.2f MB", sizeKB / 1024.0)
                                                           : String(format: "%.2f KB", sizeKB)
                            print("  📄 \(file.lastPathComponent) — \(sizeString)")
                            
                        } catch {
                            print("  ❌ Error reading \(file.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
            }
            
            // Print total size for this folder
            let totalMB = Double(totalSize) / (1024.0 * 1024.0)
            print("📦 Total \(name) folder size: \(String(format: "%.2f MB", totalMB))\n")
        }
    }

    
    private func playCurrent() {
        guard currentIndex < ads.count else { return }
        let ad = ads[currentIndex]
        currentAd = ad

        withAnimation(.easeInOut(duration: 0.5)) { transitionOpacity = 0.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.5)) { self.transitionOpacity = 1.0 }
        }

        if ad.assettype.lowercased() == "video" {
            playVideo(ad)
        } else {
            playImageAd()
        }
    }

    private func playVideo(_ ad: AdItemModel) {
        guard let localURL = localURLs[ad.itemid] else {
            playNext(); return
        }

        player = AVPlayer(url: localURL)
        player?.play()

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            self?.playNext()
        }
    }

    private func playImageAd() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.playNext()
        }
    }

    private func playNext() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        currentIndex += 1
        if currentIndex >= ads.count { currentIndex = 0 }
        playCurrent()
    }

    func localURL(for ad: AdItemModel) -> URL? {
        localURLs[ad.itemid]
    }
}
