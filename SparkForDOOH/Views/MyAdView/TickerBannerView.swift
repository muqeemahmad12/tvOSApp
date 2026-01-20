//
//  TickerBannerView.swift
//  SparkForDOOH
//
//  Displays scrolling ticker message, logo, time and weather overlay during ad playback.
//

import SwiftUI

/// Ticker banner overlay that displays during ad playback.
/// Layout: Logo (top-left), Time + Weather (top-right), Ticker (bottom)
struct TickerBannerView: View {
    let tickerMessage: String?
    let logoUrl: String?
    let showTime: Bool
    
    @State private var tickerOffset: CGFloat = 0
    @State private var logoImage: UIImage?
    @State private var currentTime: String = ""
    @StateObject private var weatherService = WeatherService.shared
    
    private let tickerHeight: CGFloat = 80
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
            // Top bar: Logo (left) and Time + Weather (right)
            HStack(alignment: .top) {
                // Hospital Logo in top-left corner (always shown)
                HospitalLogoView(logoImage: logoImage)
                    .padding(20)
                
                Spacer()
                
                // Time + Weather in top-right
                if showTime {
                    TimeWeatherView(
                        currentTime: currentTime,
                        weather: weatherService.currentWeather
                    )
                    .padding(20)
                }
            }
            
            Spacer()
            
            // Ticker at bottom - scrolls forever (capsule style)
            if let message = tickerMessage, !message.isEmpty {
                TickerScrollView(message: message, height: tickerHeight)
                    .clipShape(Capsule())
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            loadLogo()
            updateTime()
            weatherService.startWeatherUpdates()
        }
        .onDisappear {
            weatherService.stopWeatherUpdates()
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

/// Hospital logo display in top-left corner (logo only, no text)
struct HospitalLogoView: View {
    let logoImage: UIImage?
    
    var body: some View {
        Group {
            if let logo = logoImage {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 320)  // Match screenshot size
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            // If no logo URL provided, show nothing (no default icon)
        }
    }
}

/// Displays current time and weather with a subtle background
struct TimeWeatherView: View {
    let currentTime: String
    let weather: WeatherData?
    
    var body: some View {
        HStack(spacing: 16) {
            // Time with clock icon
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                
                Text(currentTime)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 30)
            
            // Weather
            if let weather = weather {
                HStack(spacing: 8) {
                    Image(systemName: weather.condition.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("\(weather.temperature)°C")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.2))
                .background(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

/// Scrolling ticker text view
struct TickerScrollView: View {
    let message: String
    let height: CGFloat
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    
    private let scrollSpeed: CGFloat = 100 // points per second
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Capsule transparent background matching top-right style
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
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
                .padding(.horizontal, 30)  // Padding inside capsule
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
