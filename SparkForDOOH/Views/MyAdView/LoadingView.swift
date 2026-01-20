//
//  LoadingView.swift
//  SparkForDOOH
//
//  Shared loading screen while ads are preloading or when there is no data yet.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            FullscreenBackground(imageName: "placeholder_image")

            VStack {
                Text("Loading Informational Sparks \n for your clinical display")
                    .font(.system(size: 90))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#138bcc"))
                    .padding(.top, 50)

                Text("Your display will start automatically once the initial download is complete.")
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#505050"))

                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image("tv_frame")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 1050)
                        .padding(.trailing, 35)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}


