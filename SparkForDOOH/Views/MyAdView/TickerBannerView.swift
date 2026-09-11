//
//  TickerBannerView.swift
//  SparkForDOOH
//
//  Displays scrolling ticker message, logo, and time overlay during ad playback.
//

import SwiftUI

/// Ticker banner overlay that displays during ad playback.
/// Layout: Logo (top-left), Time (top-right), Ticker (bottom)
struct TickerBannerView: View {
    let tickerMessage: String?
    let logoUrl: String?
    let showTime: Bool
    
    @State private var logoImage: UIImage?
    @State private var currentTime: String = ""
    
    private let tickerHeight: CGFloat = 56
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(tickerMessage: String?, logoUrl: String?, showTime: Bool = true) {
        self.tickerMessage = tickerMessage
        self.logoUrl = logoUrl
        self.showTime = showTime
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                HospitalLogoView(logoImage: logoImage)
                    .padding(20)
                
                Spacer()
                
                if showTime {
                    TimeDisplayView(currentTime: currentTime)
                        .padding(20)
                }
            }
            
            Spacer()
            
            if let message = tickerMessage, !message.isEmpty {
                TickerScrollView(message: message, height: tickerHeight)
                    .clipShape(Capsule())
                    .padding(.horizontal, 28)
                    .padding(.bottom, 21)
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

/// Hospital logo display in top-left corner (logo only, no text)
struct HospitalLogoView: View {
    let logoImage: UIImage?
    
    var body: some View {
        Group {
            if let logo = logoImage {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
    }
}

/// Current time with a subtle background
struct TimeDisplayView: View {
    let currentTime: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
            
            Text(currentTime)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
                .background(
                    Capsule()
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
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
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.5), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
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
                    
                    Text(message)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize()
                        .offset(x: offset + textWidth + 100)
                }
                .padding(.horizontal, 30)
            }
        }
        .frame(height: height)
    }
    
    private func startScrolling(containerWidth: CGFloat) {
        offset = containerWidth
        let totalDistance = containerWidth + textWidth + 100
        let duration = Double(totalDistance / scrollSpeed)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -textWidth - 100
        }
    }
}
