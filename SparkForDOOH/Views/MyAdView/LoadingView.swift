//
//  LoadingView.swift
//  SparkForDOOH
//
//  Shared loading screen while ads are preloading or when there is no data yet.
//

import SwiftUI

struct LoadingView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background artwork
                Image("loading_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                // Foreground content
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Loading Informational \nSparks for your \nclinical display")
                            .font(.system(size: 65, weight: .semibold))
                            .foregroundColor(Color(hex: "#138bcc"))
                            .multilineTextAlignment(.leading)

                        Text("Your display will start automatically\nonce the initial download is complete.")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundColor(Color(hex: "#505050"))
                            .multilineTextAlignment(.leading)
                            .padding(.top, 30)

                        Spacer(minLength: 0)
                    }
                    .frame(width: geo.size.width * 0.30, alignment: .leading)
                    .padding(.leading, 80)
                    .padding(.top, 170)

                    Image("loading_screen")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(geo.size.width * 0.65, 2000))
                        .padding(.trailing, 0)
                        .layoutPriority(1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }
        }
    }
}


