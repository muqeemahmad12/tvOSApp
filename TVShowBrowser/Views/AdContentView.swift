//
//  AdContentView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI
import AVKit

struct AdContentView: View {
    let ad: UIAdType
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            switch ad {
            case .image(let url):
                AsyncImage(url: URL(string: url)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }

            case .video(let url):
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                            setupLoop(for: player)
                        }
                        .onDisappear {
                            player.pause()
                            removeLoopObserver(from: player)
                        }
                } else {
                    ProgressView()
                        .onAppear {
                            preloadVideo(url)
                        }
                }

            case .lottie(let name):
                LottieAdView(animationName: name)
            case .vast(url: let url):
                VastView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Helpers
    private func preloadVideo(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        player = AVPlayer(url: url)
    }

    private func setupLoop(for player: AVPlayer) {
        // Remove previous observer (if any) and re-add
        removeLoopObserver(from: player)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }

    private func removeLoopObserver(from player: AVPlayer) {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }
}
