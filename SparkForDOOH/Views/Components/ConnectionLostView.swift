//
//  ConnectionLostView.swift
//  SparkForDOOH
//
//  Full-screen offline screen shown when network is unavailable.
//

import SwiftUI
import UIKit

struct ConnectionLostView: View {
    private var connectionImage: Image {
        if let uiImage = UIImage(named: "connection_lost") {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "wifi.slash")
    }
    
    var body: some View {
        ZStack {
            // Soft radial background similar to provided reference
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.86, green: 0.94, blue: 1.0),
                    Color.white
                ]),
                center: .center,
                startRadius: 100,
                endRadius: 900
            )
            .overlay(
                Circle()
                    .stroke(Color.blue.opacity(0.08), lineWidth: 140)
                    .scaleEffect(1.1)
                    .offset(x: -40, y: 120)
            )
            .ignoresSafeArea()
            
            HStack(alignment: .center, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Connection Lost")
                        .font(.system(size: 50, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.0, green: 0.46, blue: 0.93))
                    
                    Text("This screen is currently offline and can’t download or play updated content.")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(Color(red: 0.20, green: 0.22, blue: 0.24))
                        .lineSpacing(4)
                    
                    Text("""
Please check power and internet (Wi-Fi/Ethernet) for this device. If the network is stable, restart the screen/app and confirm the connection is restored. If the issue continues, contact your IT to verify firewall/network access and reconnect this screen.
""")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(Color(red: 0.24, green: 0.25, blue: 0.27))
                        .lineSpacing(4)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                .padding(.leading, 60)
                
                Spacer()
                
                connectionImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 460, maxHeight: 360)
                    .foregroundColor(Color(red: 0.0, green: 0.46, blue: 0.93))
                    .padding(.trailing, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    ConnectionLostView()
}

