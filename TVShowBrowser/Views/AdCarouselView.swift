//
//  AdCarouselView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Foundation
import SwiftUI

struct AdCarouselView: View {
    let ads: [UIAdType]
    @State private var currentIndex = 0

    var body: some View {
        VStack {
            AdRendererView()
                .frame(height: 400)
                .focusable(true)

            HStack {
                Button("Prev") { currentIndex = (currentIndex - 1 + ads.count) % ads.count }
                    .buttonStyle(.borderedProminent)
                    .focusable(true)

                Button("Next") { currentIndex = (currentIndex + 1) % ads.count }
                    .buttonStyle(.borderedProminent)
                    .focusable(true)
            }
        }
        .onAppear { startAutoRotation() }
    }

    private func startAutoRotation() {
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            currentIndex = (currentIndex + 1) % ads.count
        }
    }
}
