//
//  LottieAdView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 08/10/25.
//

import Lottie
import SwiftUI

struct LottieAdView: UIViewRepresentable {
    let animationName: String
    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animationName)
        view.loopMode = .loop
        view.play()
        return view
    }
    func updateUIView(_ uiView: LottieAnimationView, context: Context) {}
}
