//
//  VastView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 21/10/25.
//

import SwiftUI

struct VastView: View {
    @State private var progress: Float = 0
    @State private var isPlayingContent = false

    let contentURL = URL(string: "https://storage.googleapis.com/interactive-media-ads/media/stock.mp4")!
    let adTagURL = "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&correlator="

    var body: some View {
        // Use fixed 1920x1080 (Full HD tvOS layout)
        ZStack(alignment: .topLeading) {
            Color.black.edgesIgnoringSafeArea(.all)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // 🎬 Video Player (Top Left)
                    ZStack(alignment: .bottom) {
                        VASTPlayerView(
                            contentURL: contentURL,
                            adTagURL: adTagURL,
                            adProgress: $progress,
                            isPlayingContent: $isPlayingContent
                        )
                        .frame(width: 1400, height: 810) // 75% height, 75% width

                        if progress > 0 && progress < 1 {
                            ProgressView(value: progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(height: 6)
                                .padding(.horizontal, 20)
                        }
                    }

                    // 🟥 Bottom Banner (Below video)
                    AsyncImage(url: URL(string: "https://picsum.photos/seed/bottomBanner/1400/270")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 1400, height: 270)
                }

                // 🟩 Right Banner (Side ad)
                AsyncImage(url: URL(string: "https://simage.doceree.com/spark-dooh/9x16_banner.jpg")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 520, height: 1080)
            }
        }
    }
}
