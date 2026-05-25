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
            // Background image
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connection Lost")
                        .font(.system(size: 65, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.91))
                    
                    Text("This screen is currently offline and can’t download or play updated content.")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: 920, alignment: .leading)
                        .padding(.trailing, 8)
                        .padding(.bottom, 100) // extra gap before description
                    
                    Text("Please check power and internet (Wi-Fi/Ethernet) for this device. If the network is stable, restart the screen/app and confirm the connection is restored. If the issue continues, contact your IT to verify firewall/network access and reconnect this screen.")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: 980, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
                
                Spacer()
                
                Image("connection_lost")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 560, maxHeight: 438) // keeps 1122x876 aspect (~1.28:1)
                    .padding(.trailing, 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.top, -100) // shift entire stack upward
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

