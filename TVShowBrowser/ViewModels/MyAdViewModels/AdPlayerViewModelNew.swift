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
        guard !ads.isEmpty else { return }
        self.ads = ads.sorted { $0.sequence < $1.sequence }
        preloadAllAssets()
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
