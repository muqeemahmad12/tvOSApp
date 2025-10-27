//
//  HeroBannerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import SwiftUI

struct HeroBannerView: View {
    let ads: [UIAdType]
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            AdRendererView()
                .frame(height: 400)
                .cornerRadius(12)
                .shadow(radius: 10)
                .focusable(false)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentIndex = (currentIndex + 1) % ads.count
                    // TODO: Trigger impression API here
                    print("Impression: Hero Banner Index \(currentIndex)")
                }
            }
        }
    }
}
