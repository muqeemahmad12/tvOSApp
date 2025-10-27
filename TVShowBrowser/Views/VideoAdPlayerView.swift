//
//  VideoAdPlayerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI
import AVKit

struct VideoAdPlayerView: View {
    let videoURL: String
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                ProgressView("Loading video...")
                    .onAppear {
                        if let url = URL(string: videoURL) {
                            player = AVPlayer(url: url)
                        }
                    }
            }
        }
    }
}
