//
//  TickerBannerView.swift
//  SparkForDOOH
//
//  Displays scrolling ticker message and optional logo overlay during ad playback.
//

import SwiftUI

/// Ticker banner overlay that displays at the bottom of the screen during ad playback.
/// Shows a scrolling ticker message and optional logo.
struct TickerBannerView: View {
    let tickerMessage: String?
    let logoUrl: String?
    
    @State private var tickerOffset: CGFloat = 0
    @State private var logoImage: UIImage?
    
    private let tickerHeight: CGFloat = 60
    private let logoSize: CGFloat = 80
    
    var body: some View {
        VStack {
            // Logo in top-right corner
            if let logoImage = logoImage {
                HStack {
                    Spacer()
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: logoSize, height: logoSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .padding(20)
                }
            }
            
            Spacer()
            
            // Ticker at bottom
            if let message = tickerMessage, !message.isEmpty {
                TickerScrollView(message: message, height: tickerHeight)
            }
        }
        .onAppear {
            loadLogo()
        }
        .onChange(of: logoUrl) { _ in
            loadLogo()
        }
    }
    
    private func loadLogo() {
        guard let urlString = logoUrl, let url = URL(string: urlString) else {
            logoImage = nil
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.logoImage = image
                    }
                }
            } catch {
                print("⚠️ Failed to load logo: \(error.localizedDescription)")
            }
        }
    }
}

/// Scrolling ticker text view
struct TickerScrollView: View {
    let message: String
    let height: CGFloat
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    
    private let scrollSpeed: CGFloat = 50 // points per second
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.8),
                        Color.black.opacity(0.9)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Scrolling text
                HStack(spacing: 0) {
                    Text(message)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize()
                        .background(
                            GeometryReader { textGeometry in
                                Color.clear.onAppear {
                                    textWidth = textGeometry.size.width
                                    startScrolling(containerWidth: geometry.size.width)
                                }
                            }
                        )
                        .offset(x: offset)
                    
                    // Duplicate text for seamless scrolling
                    Text(message)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize()
                        .offset(x: offset + textWidth + 100)
                }
            }
        }
        .frame(height: height)
    }
    
    private func startScrolling(containerWidth: CGFloat) {
        // Start from right edge
        offset = containerWidth
        
        // Calculate animation duration based on distance and speed
        let totalDistance = containerWidth + textWidth + 100
        let duration = Double(totalDistance / scrollSpeed)
        
        // Animate continuously
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -textWidth - 100
        }
    }
}
