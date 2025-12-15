//
//  FullscreenBackground.swift
//  SparkForDOOH
//
//  A simple reusable full-screen background image view.
//

import SwiftUI

struct FullscreenBackground: View {
    let imageName: String

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
    }
}






