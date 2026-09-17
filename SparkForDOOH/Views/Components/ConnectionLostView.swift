//
//  ConnectionLostView.swift
//  SparkForDOOH
//
//  Full-screen offline screen shown when network is unavailable.
//

import SwiftUI
import UIKit

struct ConnectionLostView: View {
    var body: some View {
        ZStack {
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            GeometryReader { geo in
                let isWide = geo.size.width > geo.size.height
                let illustrationSide = min(geo.size.height * 0.48, geo.size.width * 0.30)
                let textMaxWidth = min(geo.size.width * 0.52, 980)

                HStack(alignment: .center, spacing: isWide ? 40 : 24) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Connection Lost")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.91))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("This screen is currently offline and can’t download or play updated content.")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Please check power and internet (Wi-Fi/Ethernet) for this device. If the network is stable, restart the screen/app and confirm the connection is restored. If the issue continues, contact your IT to verify firewall/network access and reconnect this screen.")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 36)
                    }
                    .frame(maxWidth: textMaxWidth, alignment: .leading)
                    .layoutPriority(1)
                    .padding(.leading, 60)

                    Spacer(minLength: 16)

                    Image("connection_lost")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: illustrationSide, height: illustrationSide)
                        .padding(.trailing, 80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            SentryService.shared.track(SentryAnalyticsEvent.errorScreenConnectionLost, attributes: [:])
            SentryService.shared.breadcrumb(category: "error_ui", message: "connection_lost_visible", data: [:])
        }
    }
}

#Preview {
    ConnectionLostView()
}
