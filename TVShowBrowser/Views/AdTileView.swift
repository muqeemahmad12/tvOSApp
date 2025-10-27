//
//  AdTileView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI
import AVKit
//import Lottie

struct AdTileView: View {
    let ad: UIAdType
    @Binding var isFocused: Bool
    @State private var adProgress: Float = 0.0
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            switch ad {
            case .image(let url):
                AsyncImage(url: URL(string: url)) { image in
                    image.resizable()
                        .scaledToFill()
                        .clipped()
                } placeholder: {
                    ProgressView()
                }

            case .video(let url):
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear { if isFocused { player.play() } }
                        .onDisappear { player.pause() }
                } else {
                    ProgressView("Loading video…")
                        .onAppear { preloadVideo(urlString: url) }
                }

            case .lottie(let name):
                LottieAdView(animationName: name)
            case .vast(url: let url):
                VastView()
            }
        }
        .frame(width: isFocused ? 300 : 250, height: isFocused ? 200 : 160)
        .cornerRadius(12)
        .shadow(color: isFocused ? .white.opacity(0.7) : .clear, radius: 10)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .focusable(true) { focused in
            isFocused = focused
            handleVideoFocus()
        }
    }

    private func handleVideoFocus() {
        guard case .video(_) = ad else { return }
        if isFocused {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private func preloadVideo(urlString: String) {
        guard player == nil, let url = URL(string: urlString) else { return }
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
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
