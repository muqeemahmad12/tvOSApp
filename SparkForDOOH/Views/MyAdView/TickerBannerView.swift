//
//  TickerBannerView.swift
//  SparkForDOOH
//
//  Displays scrolling ticker message, logo, and time overlay during ad playback.
//

import SwiftUI

/// Ticker banner overlay that displays at the bottom of the screen during ad playback.
/// Shows a scrolling ticker message, optional logo, and current time.
struct TickerBannerView: View {
    let tickerMessage: String?
    let logoUrl: String?
    let showTime: Bool
    
    @State private var tickerOffset: CGFloat = 0
    @State private var logoImage: UIImage?
    @State private var currentTime: String = ""
    
    private let tickerHeight: CGFloat = 60
    private let logoSize: CGFloat = 80
    
    // Timer for updating clock
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(tickerMessage: String?, logoUrl: String?, showTime: Bool = true) {
        self.tickerMessage = tickerMessage
        self.logoUrl = logoUrl
        self.showTime = showTime
    }
    
    var body: some View {
        VStack {
            // Top bar: Time (left) and Logo (right)
            HStack(alignment: .top) {
                // Time display in top-left
                if showTime {
                    TimeDisplayView(currentTime: currentTime)
                        .padding(20)
                }
                
                Spacer()
                
                // Logo in top-right corner
                if let logoImage = logoImage {
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
            updateTime()
        }
        .onChange(of: logoUrl) { _ in
            loadLogo()
        }
        .onReceive(clockTimer) { _ in
            updateTime()
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTime = formatter.string(from: Date())
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

/// Displays current time with a subtle background
struct TimeDisplayView: View {
    let currentTime: String
    
    var body: some View {
        Text(currentTime)
            .font(.system(size: 32, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.6))
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
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
