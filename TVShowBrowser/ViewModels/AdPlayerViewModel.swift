//
//  AdPlayerViewModel.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation
import AVFoundation
import Combine

final class AdPlayerViewModel: ObservableObject {
    @Published var ads: [UIAdType] = []
    @Published var currentIndex: Int = 0

    private var players: [URL: AVPlayer] = [:]

    func loadSampleAds() {
        ads = [
            .video(url: "https://www.w3schools.com/html/mov_bbb.mp4"),
            .image(url: "https://picsum.photos/800/400"),
            .vast(url: "https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&iu=/124319096/external/ad_rule_samples&ciu_szs=300x250&ad_rule=1&impl=s&gdfp_req=1&env=vp&output=vast&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ct%3Dlinear&correlator=")
            ]
        preloadVideos()
    }

    private func preloadVideos() {
        for ad in ads {
            guard case .video(let urlString) = ad,
                  let url = URL(string: urlString),
                  players[url] == nil else { continue }

            let asset = AVURLAsset(url: url)
            // ask the asset to load playable (and any keys you need)
            asset.loadValuesAsynchronously(forKeys: ["playable"]) {
                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)

                if status == .loaded {
                    // create player item and configure buffering behavior
                    let item = AVPlayerItem(asset: asset)
                    item.preferredForwardBufferDuration = 5 // seconds of forward buffer (adjust)
                    
                    let player = AVPlayer(playerItem: item)
                    player.automaticallyWaitsToMinimizeStalling = false

                    DispatchQueue.main.async {
                        self.players[url] = player
                    }
                } else {
                    // handle errors / fallback
                    print("Failed to load asset playable: \(String(describing: error))")
                }
            }
        }
    }

    func player(for urlString: String) -> AVPlayer? {
        guard let url = URL(string: urlString) else { return nil }
        return players[url]
    }
}
