//
//  AdRendererView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI
import AVKit
//import Lottie

// MARK: - AdRow
struct AdRow: Codable, Identifiable {
    let id = UUID()
    let title: String
    let ads: [AdItem]

    // Since UUID() is not part of the JSON, we manually define CodingKeys
    enum CodingKeys: String, CodingKey {
        case title
        case ads
    }
}

// MARK: - AdConfig
struct AdConfig: Codable {
    let heroAds: [AdItem]
    let adRows: [AdRow]
}

// MARK: - Ad Renderer View
struct AdRendererView: View {
    @StateObject private var viewModel = AdRendererViewModel()
    @State private var adProgress: Float = 0.0
    
    var body: some View {
        ZStack {
            if let ad = viewModel.currentAd {
                switch ad {
                case .image(let url):
                    AsyncImage(url: URL(string: url)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 800, maxHeight: 400)
                    } placeholder: {
                        ProgressView()
                    }
                case .video(let url):
                    VideoAdPlayerView(videoURL: url)
                case .lottie(let name):
                    LottieAdView(animationName: name)
                case .vast(url: let url):
                    VastView()
                }
            } else {
                ProgressView("Loading Ads…")
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 1.0), value: viewModel.currentAd)
        .frame(width: 1000, height: 600)
        .background(Color.black)
        .cornerRadius(16)
        .shadow(radius: 8)
    }
}
