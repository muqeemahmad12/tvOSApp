//
//  NonInteractiveVideoPlayer.swift
//  SparkForDOOH
//
//  AVPlayerLayer wrapper that does not take tvOS focus / steal the Menu button
//  (unlike SwiftUI `VideoPlayer` / AVPlayerViewController).
//

import AVFoundation
import SwiftUI
import UIKit

struct NonInteractiveVideoPlayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }

    final class PlayerLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                playerLayer.videoGravity = .resizeAspectFill
            }
        }

        override var canBecomeFocused: Bool { false }
    }
}
