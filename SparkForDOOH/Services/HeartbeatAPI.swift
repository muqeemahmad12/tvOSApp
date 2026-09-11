//
//  HeartbeatAPI.swift
//  SparkForDOOH
//
//  Sends periodic heartbeat signals to the backend for device health monitoring.
//

import Foundation
import UIKit

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when ticker/logo is updated from heartbeat response
    static let tickerUpdated = Notification.Name("com.doceree.sparkfordooh.tickerUpdated")

    /// Posted when the first heartbeat returns screenStatus ACTIVE (unlock landing gate)
    static let initialHeartbeatSucceeded = Notification.Name("com.doceree.sparkfordooh.initialHeartbeatSucceeded")

    /// Posted when the first heartbeat fails or screenStatus is not ACTIVE (route to registration/activation)
    static let initialHeartbeatFailed = Notification.Name("com.doceree.sparkfordooh.initialHeartbeatFailed")

    /// Posted when a heartbeat response has data.screenStatus == "INACTIVE" (screen deactivated remotely).
    static let heartbeatScreenStatusInactive = Notification.Name("com.doceree.sparkfordooh.heartbeatScreenStatusInactive")
}

/// Heartbeat API for sending device status to the backend.
/// This enables remote monitoring and can receive updated configuration (ticker, logo).
final class HeartbeatAPI {
    static let shared = HeartbeatAPI()
    private init() {}
    
    /// Heartbeat response model (code, message, data.screenStatus / logoUrl / tickerMessage)
    struct HeartbeatResponse: Codable {
        let timestamp: String?
        let code: Int?
        let status: String?
        let message: String?
        let data: HeartbeatResponseData?
    }

    struct HeartbeatResponseData: Codable {
        let screenStatus: String?
        let logoUrl: String?
        let tickerMessage: String?
    }

    /// Outcome of a single heartbeat request (gate unlocks only on `.active`).
    enum SendResult {
        case active(HeartbeatResponseData?)
        case inactive(HeartbeatResponseData?)
        case requestFailed
    }
    
    /// Heartbeat interval in seconds (20 minutes)
    private let heartbeatInterval: TimeInterval = 20 * 60
    
    /// Timer for periodic heartbeat
    private var heartbeatTimer: Timer?
        
    /// Flag to indicate we already unlocked the gate with ACTIVE once this process
    private var initialHeartbeatSucceeded = false
    /// Prevents concurrent duplicate initial heartbeats.
    private var isInitialHeartbeatInFlight = false
    
    /// Current playback info for heartbeat payload
    private var currentSequenceIndex: Int = 0
    private var currentAdId: String = ""
    private var isPlaying: Bool = false
    private var lastSyncTime: Date?
    private var lastPlayedTime: Date?
    
    // MARK: - Public Methods
    
    /// Start the 20‑minute heartbeat timer (does not fire immediately).
    func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        
        print("💓 Starting heartbeat service (interval: \(Int(heartbeatInterval))s)")
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task {
                _ = await self?.sendHeartbeat()
            }
        }
    }
    
    /// Stop the heartbeat timer
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        print("💔 Heartbeat service stopped")
    }
    
    /// Update current playback status (called by AdPlayerViewModel)
    func updatePlaybackStatus(sequenceIndex: Int, adId: String, isPlaying: Bool) {
        self.currentSequenceIndex = sequenceIndex
        self.currentAdId = adId
        self.isPlaying = isPlaying
        self.lastPlayedTime = Date()
    }
    
    /// Update last sync time (called after successful playlist sync)
    func updateLastSyncTime() {
        self.lastSyncTime = Date()
    }

    /// Allow another launch-gate heartbeat (e.g. after reconnect while still gated).
    func resetInitialHeartbeatGate() {
        initialHeartbeatSucceeded = false
        isInitialHeartbeatInFlight = false
    }
    
    /// One heartbeat on launch/restart. Unlocks only when `screenStatus == ACTIVE`.
    /// Requires poll `secureKey` as `x-api-key`.
    func startInitialHeartbeat() {
        Task { @MainActor in
            guard initialHeartbeatSucceeded == false else { return }
            guard !isInitialHeartbeatInFlight else {
                print("💓 Initial heartbeat skipped — already in flight")
                return
            }

            guard AppRootViewModel.hasSavedSecureKey() else {
                print("🆕 No secureKey — skip heartbeat (first-time / not activated)")
                return
            }

            isInitialHeartbeatInFlight = true
            print("💓 Initial heartbeat check starting (x-api-key=poll secureKey, require ACTIVE)")

            let result = await sendHeartbeat()
            isInitialHeartbeatInFlight = false

            switch result {
            case .active:
                markInitialHeartbeatSucceeded()
            case .inactive(let data):
                applyHeartbeatOverlayConfig(from: data)
                AppRootViewModel.clearActivation()
                print("⏳ Heartbeat screenStatus INACTIVE — routing to registration/activation")
                SentryService.shared.track(SentryAnalyticsEvent.initialHeartbeatFailed, attributes: ["reason": "inactive"])
                SentryService.shared.breadcrumb(category: "heartbeat", message: "initial_inactive", data: [:])
                NotificationCenter.default.post(name: .initialHeartbeatFailed, object: nil)
            case .requestFailed:
                print("⏳ Initial heartbeat failed; routing to registration/activation")
                SentryService.shared.track(SentryAnalyticsEvent.initialHeartbeatFailed, attributes: ["reason": "request_failed"])
                SentryService.shared.breadcrumb(category: "heartbeat", message: "initial_failed", data: [:])
                NotificationCenter.default.post(name: .initialHeartbeatFailed, object: nil)
            }
        }
    }
    
    private func markInitialHeartbeatSucceeded() {
        initialHeartbeatSucceeded = true
        print("✅ Initial heartbeat ACTIVE — unlocking app")
        SentryService.shared.track(SentryAnalyticsEvent.initialHeartbeatSuccess)
        SentryService.shared.breadcrumb(category: "heartbeat", message: "initial_ok", data: [:])
        NotificationCenter.default.post(name: .initialHeartbeatSucceeded, object: nil)
        startHeartbeat()
    }
    
    /// Get current network status
    private func getNetworkStatus() -> String {
        return "connected"
    }
    
    // MARK: - Private Methods
    
    /// Send a single heartbeat to the backend.
    /// `x-api-key` is always the poll `secureKey`. Gate unlocks only on ACTIVE.
    @discardableResult
    private func sendHeartbeat() async -> SendResult {
        await TVRemoteConfigService.waitUntilLaunchConfigNetworkFinished()
        let url = TVRemoteConfigStore.shared.activationURL(pathComponents: "dooh", "device", "heartbeat")
        
        let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let secureKey = await MainActor.run { AppRootViewModel.getSavedSecureKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        let deviceCode = await AppRootViewModel.getSavedDeviceCode() ?? ""

        guard !secureKey.isEmpty else {
            print("⚠️ Heartbeat skipped — no poll secureKey for x-api-key")
            return .requestFailed
        }
        
        // Format timestamps
        let isoFormatter = ISO8601DateFormatter()
        let lastSyncString = lastSyncTime.map { isoFormatter.string(from: $0) } ?? ""
        let lastPlayedString = lastPlayedTime.map { isoFormatter.string(from: $0) } ?? ""
        
        let payload: [String: Any] = await [
            // Required fields per spec
            "screen_id": AppConfig.current.screenId,
            "device_id": deviceId,
            "last_sync": lastSyncString,
            "last_played": lastPlayedString,
            "network_status": getNetworkStatus(),
            // Additional context fields
            "deviceCode": deviceCode,
            "secureKey": secureKey,
            "timestamp": isoFormatter.string(from: Date()),
            "status": isPlaying ? "playing" : "idle",
            "currentSequence": currentSequenceIndex,
            "currentAdId": currentAdId,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "osVersion": UIDevice.current.systemVersion,
            "environment": TVRemoteConfigStore.shared.environmentLabel
        ]
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Always use poll secureKey as x-api-key (same as quest).
            request.setValue(secureKey, forHTTPHeaderField: "x-api-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.timeoutInterval = 30

            print("💓 Heartbeat POST \(url.absoluteString)")
            print("   x-api-key (secureKey): \(secureKey)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ Heartbeat: Invalid response")
                return .requestFailed
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                print("💓 Heartbeat OK (HTTP \(httpResponse.statusCode))")
                guard let heartbeatResponse = try? JSONDecoder().decode(HeartbeatResponse.self, from: data) else {
                    print("💓 Raw response: \(String(data: data, encoding: .utf8) ?? "")")
                    return .requestFailed
                }

                let body = heartbeatResponse.data
                let responseForm: [String: Any] = [
                    "code": heartbeatResponse.code ?? 0,
                    "status": heartbeatResponse.status ?? "",
                    "message": heartbeatResponse.message ?? "",
                    "data": [
                        "screenStatus": body?.screenStatus ?? "",
                        "logoUrl": body?.logoUrl ?? "",
                        "tickerMessage": body?.tickerMessage ?? ""
                    ]
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: responseForm),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("💓 Heartbeat response: \(jsonString)")
                }

                NetworkMonitor.shared.markOnline(reason: "HeartbeatSuccess")

                let screenStatus = body?.screenStatus?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""

                await MainActor.run {
                    applyHeartbeatOverlayConfig(from: body)
                }

                if screenStatus == "ACTIVE" {
                    return .active(body)
                }

                // Non-ACTIVE (INACTIVE or missing) — do not unlock the app.
                if screenStatus == "INACTIVE" {
                    await MainActor.run {
                        // Mid-session periodic heartbeats also use this path.
                        if initialHeartbeatSucceeded {
                            NotificationCenter.default.post(name: .heartbeatScreenStatusInactive, object: nil)
                        }
                    }
                    return .inactive(body)
                }

                print("⚠️ Heartbeat screenStatus '\(body?.screenStatus ?? "nil")' — not ACTIVE")
                return .inactive(body)
            } else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ Heartbeat failed: HTTP \(httpResponse.statusCode) — \(raw)")
                return .requestFailed
            }
        } catch {
            print("❌ Heartbeat error: \(error.localizedDescription)")
            return .requestFailed
        }
    }

    /// Apply logo/ticker from heartbeat: non-empty updates, empty clears that item, nil leaves cache.
    @MainActor
    private func applyHeartbeatOverlayConfig(from data: HeartbeatResponseData?) {
        guard let data else { return }

        let previousTicker = AppRootViewModel.getSavedTickerMessage()
        let previousLogo = AppRootViewModel.getSavedLogoUrl()

        // Heartbeat `data` includes these fields: empty/null means remove from cache.
        AppRootViewModel.updateTickerMessage(data.tickerMessage ?? "")
        AppRootViewModel.updateLogoUrl(data.logoUrl ?? "")

        let tickerChanged = AppRootViewModel.getSavedTickerMessage() != previousTicker
        let logoChanged = AppRootViewModel.getSavedLogoUrl() != previousLogo
        guard tickerChanged || logoChanged else { return }

        NotificationCenter.default.post(name: .tickerUpdated, object: nil)
        print("📢 Heartbeat overlay updated (tickerChanged=\(tickerChanged), logoChanged=\(logoChanged))")
    }
}
