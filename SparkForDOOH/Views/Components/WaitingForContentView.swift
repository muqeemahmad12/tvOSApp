//
//  WaitingForContentView.swift
//  SparkForDOOH
//
//  Full-screen placeholder shown when the device is online but no playlist
//  has been assigned yet.
//

import SwiftUI

struct WaitingForContentView: View {
    var body: some View {
        ZStack {
            Image("registration_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            HStack(alignment: .center, spacing: 32) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Waiting for Content")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.45, blue: 0.91))
                    
                    Text("This screen is connected, but no content is assigned yet.")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 520, alignment: .leading)
                    
                    Text("""
Please contact your Facility Manager/Administrator to assign or schedule the content source to this screen. Once assigned and synced, playback will start automatically; no restart needed!
""")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.36, blue: 0.41))
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
                .padding(.top, -60) // lift text slightly
                
                Spacer()
                
                Image("waiting_for_content")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 520, maxHeight: 420)
                    .padding(.trailing, 80)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    WaitingForContentView()
}
