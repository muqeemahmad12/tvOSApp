//
//  TickerBannerView.swift
//  SparkForDOOH
//
//  Displays scrolling ticker message, logo, and time overlay during ad playback.
//

import SwiftUI
import UIKit

/// Ticker banner overlay: logo (top-left), time (top-right), marquee (bottom).
struct TickerBannerView: View {
    let tickerMessage: String?
    let logoUrl: String?
    var showTime: Bool = true

    @State private var logoImage: UIImage?
    @State private var currentTime: String = ""
    @ObservedObject private var marquee = TickerMarqueeEngine.shared

    private let tickerHeight: CGFloat = 56
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

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
            if !marquee.playingMessage.isEmpty {
                TickerScrollView(engine: marquee, height: tickerHeight)
                    .clipShape(Capsule())
                    .padding(.horizontal, 28)
                    .padding(.bottom, 21)
            }
        }
        .onAppear {
            loadLogo(from: logoUrl)
            currentTime = Self.timeFormatter.string(from: Date())
            // Ads are playing — start ticker from the beginning (not earlier via heartbeat).
            marquee.start(tickerMessage)
        }
        .onDisappear {
            marquee.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tickerUpdated)) { _ in
            loadLogo(from: AppRootViewModel.getSavedLogoUrl())
        }
        .onReceive(NotificationCenter.default.publisher(for: .heartbeatDidComplete)) { _ in
            marquee.submit(AppRootViewModel.getSavedTickerMessage())
        }
        .onReceive(clockTimer) { date in
            currentTime = Self.timeFormatter.string(from: date)
        }
    }

    private func loadLogo(from rawURL: String?) {
        guard let rawURL else {
            logoImage = nil
            return
        }
        let normalized = AppRootViewModel.normalizedLogoURLString(rawURL)
        guard !normalized.isEmpty, let url = URL(string: normalized) else {
            logoImage = nil
            return
        }
        Task {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: request)
                if let image = UIImage(data: data) {
                    await MainActor.run { self.logoImage = image }
                }
            } catch {
                print("⚠️ Failed to load logo: \(error.localizedDescription)")
            }
        }
    }
}

struct HospitalLogoView: View {
    let logoImage: UIImage?

    var body: some View {
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
                .overlay(Capsule().stroke(Color.black.opacity(0.5), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Marquee
// Loop → handoff (old exits, new behind) → ending (empty API: scroll off, hide).

@MainActor
final class TickerMarqueeEngine: ObservableObject {
    static let shared = TickerMarqueeEngine()

    @Published private(set) var playingMessage = ""
    @Published private(set) var incomingMessage: String?
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var frontCopies = 3
    @Published private(set) var behindCopies = 0

    private enum Phase { case looping, waitSeam, handoff, ending }
    private var phase: Phase = .looping
    private var distance: CGFloat = 0
    private var playingWidth: CGFloat = 0
    private var visibleWidth: CGFloat = 0
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    /// Only scroll while the ads overlay is on screen.
    private var bannerVisible = false
    /// Wait for layout width before placing the line and starting motion.
    private var waitingForWidth = false

    private let speed: CGFloat = 80
    private let gap: CGFloat = 70
    private let font = UIFont.systemFont(ofSize: 28, weight: .medium)

    // MARK: TEMP testing — remove when API ticker is reliable
    private let hardcodedRotationEnabled = false
    private let hardcodedMessages = [
        "Lavender Lane - Interview",
        "Built only for children: from emergency care to specialty clinics, our teams deliver compassionate treatment around the clock — thank you for trusting us with your family."
    ]
    /// After this many heartbeats, simulate empty API → smooth end.
    private let hardcodedClearAfterHeartbeats = 3
    private var hardcodedIndex = 0
    private var hardcodedHeartbeatCount = 0
    // MARK: end TEMP testing

    private init() {}

    /// Ads overlay appeared — put the start of the line just off the right edge, then scroll.
    func start(_ raw: String?) {
        timer?.invalidate()
        timer = nil
        bannerVisible = true
        phase = .looping
        incomingMessage = nil
        behindCopies = 0

        let next = resolveMessage(raw, countHeartbeat: false)
        guard !next.isEmpty else {
            playingMessage = ""
            waitingForWidth = false
            distance = 0
            offset = 0
            return
        }
        beginLoop(next, fromStart: true)
    }

    /// Heartbeat / API update. Ignored until ads overlay has started.
    func submit(_ raw: String?) {
        guard bannerVisible else { return }

        let next = resolveMessage(raw, countHeartbeat: true)
        if next.isEmpty {
            beginClear()
            return
        }
        if playingMessage.isEmpty || phase == .ending {
            beginLoop(next, fromStart: true)
            return
        }
        if !hardcodedRotationEnabled,
           next == playingMessage,
           incomingMessage == nil,
           phase == .looping {
            return
        }
        incomingMessage = next
        if phase == .looping { phase = .waitSeam }
        startTimer()
    }

    func updateVisibleWidth(_ width: CGFloat) {
        visibleWidth = max(0, width)
        guard bannerVisible, !playingMessage.isEmpty else { return }

        playingWidth = measure(playingMessage)

        // First layout after a fresh start — park text off the right, then move.
        if waitingForWidth, visibleWidth > 1, phase == .looping {
            waitingForWidth = false
            frontCopies = loopCopies(for: playingWidth)
            behindCopies = 0
            distance = -visibleWidth
            offset = -distance
            startTimer()
            return
        }

        guard phase == .looping, !waitingForWidth, distance < 0.5 else { return }
        frontCopies = loopCopies(for: playingWidth)
        behindCopies = 0
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        bannerVisible = false
        waitingForWidth = false
    }

    // MARK: Private

    private func resolveMessage(_ raw: String?, countHeartbeat: Bool) -> String {
        if hardcodedRotationEnabled {
            if countHeartbeat {
                hardcodedHeartbeatCount += 1
                if hardcodedHeartbeatCount > hardcodedClearAfterHeartbeats {
                    print("📢 Ticker TEST — heartbeat #\(hardcodedHeartbeatCount) empty → smooth clear")
                    return ""
                }
                let next = hardcodedMessages[hardcodedIndex % hardcodedMessages.count]
                hardcodedIndex += 1
                print("📢 Ticker TEST #\(hardcodedHeartbeatCount)/\(hardcodedClearAfterHeartbeats) → \"\(next)\"")
                return next
            }
            return hardcodedMessages[hardcodedIndex % hardcodedMessages.count]
        }
        return AppRootViewModel.singleLineTicker(raw ?? "")
    }

    private func beginClear() {
        guard !playingMessage.isEmpty, phase != .ending else { return }
        incomingMessage = ""
        if phase == .looping || phase == .handoff { phase = .waitSeam }
        startTimer()
        print("📢 Ticker smooth clear")
    }

    private func clearNow() {
        timer?.invalidate()
        timer = nil
        playingMessage = ""
        incomingMessage = nil
        phase = .looping
        distance = 0
        offset = 0
        waitingForWidth = false
        frontCopies = 3
        behindCopies = 0
    }

    /// - fromStart: ONLY for cold start (ads overlay first appear / after clear).
    ///   New text via handoff must use false — keep seamless loop, do not re-enter from the right.
    private func beginLoop(_ message: String, fromStart: Bool) {
        phase = .looping
        incomingMessage = nil
        playingMessage = message
        playingWidth = measure(message)
        frontCopies = loopCopies(for: playingWidth)
        behindCopies = 0

        if fromStart {
            if visibleWidth > 1 {
                waitingForWidth = false
                distance = -visibleWidth
                offset = -distance
                startTimer()
            } else {
                // Keep off-screen until GeometryReader reports width — avoids a full-bar flash.
                waitingForWidth = true
                distance = 0
                offset = 4000
            }
        } else {
            waitingForWidth = false
            distance = 0
            offset = 0
            startTimer()
        }
    }

    private func beginHandoff() {
        guard let incoming = incomingMessage else {
            phase = .looping
            return
        }
        if incoming.isEmpty {
            beginEnding()
            return
        }
        phase = .handoff
        waitingForWidth = false
        distance = 0
        offset = 0
        playingWidth = measure(playingMessage)
        frontCopies = coverCopies(for: playingWidth)
        behindCopies = max(coverCopies(for: measure(incoming)) + 1, 2)
        startTimer()
    }

    private func beginEnding() {
        phase = .ending
        incomingMessage = nil
        behindCopies = 0
        waitingForWidth = false
        playingWidth = measure(playingMessage)
        frontCopies = max(coverCopies(for: playingWidth), 1)
        distance = 0
        offset = 0
        startTimer()
        print("📢 Ticker ending — scrolling off")
    }

    private func startTimer() {
        guard bannerVisible, !waitingForWidth, timer == nil, !playingMessage.isEmpty, playingWidth > 1 else { return }
        lastTick = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard bannerVisible, !waitingForWidth, playingWidth > 1, !playingMessage.isEmpty else { return }
        let now = CACurrentMediaTime()
        let step = speed * min(CGFloat(now - lastTick), 0.05)
        lastTick = now
        distance += step

        switch phase {
        case .looping:
            // Negative distance = text still entering from the right.
            if distance >= 0, distance >= playingWidth {
                distance -= playingWidth
            }
            offset = -distance

        case .waitSeam:
            if distance >= playingWidth {
                distance = 0
                offset = 0
                if incomingMessage?.isEmpty == true || incomingMessage == nil {
                    beginEnding()
                } else {
                    beginHandoff()
                }
            } else {
                offset = -distance
            }

        case .handoff:
            offset = -distance
            if distance >= CGFloat(max(frontCopies, 1)) * playingWidth {
                if let incoming = incomingMessage, !incoming.isEmpty {
                    // Continue seamless loop — do not restart from the right.
                    beginLoop(incoming, fromStart: false)
                } else {
                    beginEnding()
                }
            }

        case .ending:
            offset = -distance
            if distance >= CGFloat(max(frontCopies, 1)) * playingWidth {
                clearNow()
            }
        }
    }

    private func measure(_ text: String) -> CGFloat {
        let w = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return max(w + gap, 1)
    }

    private func loopCopies(for segment: CGFloat) -> Int {
        let s = max(segment, 1)
        let v = max(visibleWidth, 1)
        if s >= v { return 2 }
        return max(2, Int(ceil(v / s)) + 1)
    }

    private func coverCopies(for segment: CGFloat) -> Int {
        let s = max(segment, 1)
        let v = max(visibleWidth, 1)
        if s >= v { return 1 }
        return Int(ceil(v / s))
    }
}

struct TickerScrollView: View {
    @ObservedObject var engine: TickerMarqueeEngine
    let height: CGFloat

    private let gap: CGFloat = 70
    private let horizontalPadding: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let visible = max(0, geo.size.width - horizontalPadding)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .overlay(Capsule().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                HStack(spacing: gap) {
                    ForEach(0..<engine.frontCopies, id: \.self) { _ in
                        label(engine.playingMessage)
                    }
                    if let behind = engine.incomingMessage, !behind.isEmpty {
                        ForEach(0..<engine.behindCopies, id: \.self) { _ in
                            label(behind)
                        }
                    }
                }
                .offset(x: engine.offset)
                .padding(.leading, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .clipped()
            .onAppear { engine.updateVisibleWidth(visible) }
            .onChange(of: geo.size.width) { _ in engine.updateVisibleWidth(visible) }
        }
        .frame(height: height)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
