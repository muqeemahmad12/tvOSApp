//
//  VideoAdView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import AVKit
import SwiftUI

import SwiftUI
import AVKit

struct VideoAdView: View {
    let urlString: String
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                ProgressView("Loading video…")
                    .onAppear { preloadVideo() }
            }
        }
        .frame(height: 250)
        .cornerRadius(12)
    }

    private func preloadVideo() {
        guard let url = URL(string: urlString) else { return }
        let asset = AVURLAsset(url: url)
        let keys = ["playable"]
        asset.loadValuesAsynchronously(forKeys: keys) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "playable", error: &error)
            if status == .loaded {
                DispatchQueue.main.async {
                    let item = AVPlayerItem(asset: asset)
                    player = AVPlayer(playerItem: item)
                    player?.automaticallyWaitsToMinimizeStalling = false
                }
            } else {
                print("⚠️ Video not playable: \(error?.localizedDescription ?? "Unknown")")
            }
        }
    }
}

