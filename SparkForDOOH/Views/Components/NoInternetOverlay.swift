//
//  NoInternetOverlay.swift
//  SparkForDOOH
//
//  Non-intrusive overlay shown when network connectivity is lost.
//

import SwiftUI

/// A subtle overlay indicator shown when the device loses internet connectivity.
/// Non-intrusive design that doesn't interrupt content playback.
struct NoInternetOverlay: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                // Non-intrusive indicator in top-right area
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 18, weight: .medium))
                    
                    Text("No Internet")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
                .padding(.top, 100)  // Below the time display
                .padding(.trailing, 20)
            }
            
            Spacer()
        }
    }
}

