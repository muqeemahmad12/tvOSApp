//
//  AdDetailView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 09/10/25.
//

import SwiftUI
import AVFoundation
import _AVKit_SwiftUI

struct AdDetailView: View {
    let ad: UIAdType
    @State private var adProgress: Float = 0.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                switch ad {
                case .image(let url):
                    AsyncImage(url: URL(string: url)) { image in
                        image.resizable()
                             .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }

                case .video(let url):
                    VideoPlayer(player: AVPlayer(url: URL(string: url)!))
                        .frame(width: 900, height: 600)

                case .lottie(let name):
                    LottieAdView(animationName: name)
                        .frame(width: 600, height: 400)
                case .vast(url: let url):
                    VastView()
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Ad Detail")
    }
}
