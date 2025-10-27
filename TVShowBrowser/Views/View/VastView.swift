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
    let ContentURLString = "https://storage.googleapis.com/interactive-media-ads/media/stock.mp4"
    let AdTagURLString = "https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs=300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&correlator="

    var body: some View {
        ZStack(alignment: .bottom) {
            VASTPlayerView(
                contentURL: URL(string: ContentURLString)!,
                adTagURL: AdTagURLString,
                adProgress: $progress,
                isPlayingContent: $isPlayingContent
            )
            .frame(height: 400)

            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: isPlayingContent ? .green : .blue))
                    .frame(height: 6)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)

    }
}
