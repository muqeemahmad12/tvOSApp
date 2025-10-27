//
//  AdDetailSliderView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 09/10/25.
//

import SwiftUI

struct AdDetailSliderView: View {
    let ads: [AdItem]
    let startIndex: Int

    @State private var currentIndex: Int
    @State private var timer: Timer?
    @State private var userInteracting = false

    init(ads: [AdItem], startIndex: Int) {
        self.ads = ads
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(ads.indices, id: \.self) { index in
                    AdContentView(ad: ads[index].adType)
                        .tag(index)
                        .focusable(true) { focused in
                            if focused {
                                userInteracting = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    userInteracting = false
                                }
                            }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .navigationTitle("Ad Details")
        .onAppear { startAutoSlide() }
        .onDisappear { stopAutoSlide() }
    }

    private func startAutoSlide() {
        stopAutoSlide()
        timer = Timer.scheduledTimer(withTimeInterval: ads[currentIndex].slideDuration, repeats: true) { _ in
            guard !userInteracting else { return }
            withAnimation {
                currentIndex = (currentIndex + 1) % ads.count
            }
        }
    }

    private func stopAutoSlide() {
        timer?.invalidate()
        timer = nil
    }
}
