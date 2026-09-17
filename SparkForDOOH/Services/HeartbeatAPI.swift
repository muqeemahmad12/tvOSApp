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

    /// Posted when heartbeat `screenStatus` is `INACTIVE`
    /// (keep credentials/cache; show Screen Deactivated; wait for ACTIVE).
    static let screenDidDeactivate = Notification.Name("com.doceree.sparkfordooh.screenDidDeactivate")

    /// Posted when heartbeat reports ACTIVE again (resume after INACTIVE / deactivated).
    static let heartbeatScreenStatusActive = Notification.Name("com.doceree.sparkfordooh.heartbeatScreenStatusActive")

    /// Posted when heartbeat `screenStatus` is `DELETED`
    /// (clear caches/credentials; show Screen Inactivated).
    static let screenDidInactivate = Notification.Name("com.doceree.sparkfordooh.screenDidInactivate")

    /// Posted after every successful heartbeat response (even if ticker/logo unchanged).
    static let heartbeatDidComplete = Notification.Name("com.doceree.sparkfordooh.heartbeatDidComplete")
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
        /// Rotated key from server (also accepted as `secret`).
        let secureKey: String?

        enum CodingKeys: String, CodingKey {
            case screenStatus, logoUrl, tickerMessage, secureKey, secret
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            screenStatus = try c.decodeIfPresent(String.self, forKey: .screenStatus)
            logoUrl = try c.decodeIfPresent(String.self, forKey: .logoUrl)
            tickerMessage = try c.decodeIfPresent(String.self, forKey: .tickerMessage)
            let fromSecure = try c.decodeIfPresent(String.self, forKey: .secureKey)
            let fromSecret = try c.decodeIfPresent(String.self, forKey: .secret)
            let trimmedSecure = fromSecure?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = fromSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedSecure, !trimmedSecure.isEmpty {
                secureKey = trimmedSecure
            } else if let trimmedSecret, !trimmedSecret.isEmpty {
                secureKey = trimmedSecret
            } else {
                secureKey = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(screenStatus, forKey: .screenStatus)
            try c.encodeIfPresent(logoUrl, forKey: .logoUrl)
            try c.encodeIfPresent(tickerMessage, forKey: .tickerMessage)
            try c.encodeIfPresent(secureKey, forKey: .secureKey)
        }
    }

    /// Outcome of a single heartbeat request (gate unlocks only on `.active`).
    enum SendResult {
        case active(HeartbeatResponseData?)
        /// `INACTIVE` — Screen Deactivated, keep cache, wait for ACTIVE.
        case inactive(HeartbeatResponseData?)
        /// `DELETED` — Screen Inactivated, clear and re-register.
        case deleted(HeartbeatResponseData?)
        case requestFailed
    }
    
    /// Heartbeat interval in seconds (ticker/logo updates arrive on this cadence).
    private let heartbeatInterval: TimeInterval = 1 * 60
    
    /// Timer for periodic heartbeat
    private var heartbeatTimer: Timer?
        
    /// Flag to indicate we already unlocked the gate with ACTIVE once this process
    private var initialHeartbeatSucceeded = false
    /// Prevents concurrent duplicate initial heartbeats.
    private var isInitialHeartbeatInFlight = false
    /// True after deactivation until an ACTIVE heartbeat — RootView may mount after the notification.
    private(set) var isAwaitingActiveStatus = false
    
    /// Current playback info for heartbeat payload
    private var currentSequenceIndex: Int = 0
    private var currentAdId: String = ""
    private var isPlaying: Bool = false
    private var lastSyncTime: Date?
    private var lastPlayedTime: Date?
    
    // MARK: - Public Methods
    
    /// Start the heartbeat timer (does not fire immediately).
    func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        
        print("💓 Starting heartbeat service (interval: \(Int(heartbeatInterval))s)")
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task {
                _ = await self?.sendHeartbeat()
            }
        }
    }

    /// Fire one heartbeat now (e.g. right after network restores) without waiting for the timer.
    func kickHeartbeatNow() {
        guard NetworkMonitor.shared.canMakeNetworkCalls else { return }
        Task {
            print("💓 Kick heartbeat now (network restored)")
            _ = await sendHeartbeat()
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
            guard NetworkMonitor.shared.canMakeNetworkCalls else {
                print("💓 Initial heartbeat skipped — no internet")
                return
            }
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
                // INACTIVE → Screen Deactivated: keep credentials + cache, wait for ACTIVE.
                print("⏳ Heartbeat screenStatus INACTIVE — showing deactivated screen, waiting for ACTIVE")
                isAwaitingActiveStatus = true
                SentryService.shared.track(SentryAnalyticsEvent.initialHeartbeatFailed, attributes: ["reason": "inactive"])
                SentryService.shared.breadcrumb(category: "heartbeat", message: "initial_inactive_waiting", data: [:])
                NotificationCenter.default.post(name: .screenDidDeactivate, object: nil)
                NotificationCenter.default.post(name: .initialHeartbeatSucceeded, object: nil)
                startHeartbeat()
            case .deleted:
                // DELETED → Screen Inactivated: clear and stop until re-register.
                print("🔒 Heartbeat screenStatus DELETED — showing inactivated screen")
                isAwaitingActiveStatus = false
                SentryService.shared.track(SentryAnalyticsEvent.initialHeartbeatFailed, attributes: ["reason": "deleted"])
                SentryService.shared.breadcrumb(category: "heartbeat", message: "initial_deleted", data: [:])
                NotificationCenter.default.post(name: .screenDidInactivate, object: nil)
                NotificationCenter.default.post(name: .initialHeartbeatSucceeded, object: nil)
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

    /// Call after first-time activation succeeds (no launch gate heartbeat).
    func markPlaybackSessionActive() {
        initialHeartbeatSucceeded = true
    }

#if DEBUG
    /// Manual test: simulate heartbeat `INACTIVE` (Screen Deactivated, wait for ACTIVE).
    func debugForceDeactivate() {
        isAwaitingActiveStatus = true
        print("🧪 DEBUG Force INACTIVE (deactivated)")
        NotificationCenter.default.post(name: .screenDidDeactivate, object: nil)
    }

    /// Manual test: simulate heartbeat `DELETED` → Screen Inactivated.
    func debugForceInactivate() {
        isAwaitingActiveStatus = false
        print("🧪 DEBUG Force DELETED (inactivated)")
        NotificationCenter.default.post(name: .screenDidInactivate, object: nil)
    }

    /// Manual test: simulate heartbeat `ACTIVE` after `INACTIVE`.
    func debugForceActive() {
        guard isAwaitingActiveStatus else {
            print("🧪 DEBUG Force ACTIVE ignored — not currently awaiting (force INACTIVE first)")
            return
        }
        isAwaitingActiveStatus = false
        print("🧪 DEBUG Force ACTIVE (reactivation)")
        NotificationCenter.default.post(name: .heartbeatScreenStatusActive, object: nil)
    }
#endif
    
    /// Get current network status
    private func getNetworkStatus() -> String {
        NetworkMonitor.shared.canMakeNetworkCalls ? "connected" : "disconnected"
    }
    
    // MARK: - Private Methods
    
    /// Send a single heartbeat to the backend.
    /// `x-api-key` is always the poll `secureKey`. Gate unlocks only on ACTIVE.
    @discardableResult
    private func sendHeartbeat() async -> SendResult {
        guard NetworkMonitor.shared.canMakeNetworkCalls else {
            print("💓 Heartbeat skipped — no internet")
            return .requestFailed
        }
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
                        "tickerMessage": body?.tickerMessage ?? "",
                        "secureKey": body?.secureKey ?? ""
                    ]
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: responseForm),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("💓 Heartbeat response: \(jsonString)")
                }

                NetworkMonitor.shared.markOnline(reason: "HeartbeatSuccess")

                let screenStatus = body?.screenStatus?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""

                await MainActor.run {
                    // Persist rotated secureKey/secret when server sends a new one.
                    if let newKey = body?.secureKey {
                        AppRootViewModel.updateSecureKey(newKey)
                    }
                    applyHeartbeatOverlayConfig(from: body)
                    // Always signal success so ticker can rotate even when API sends no ticker text.
                    NotificationCenter.default.post(name: .heartbeatDidComplete, object: nil)
                }

                if screenStatus == "ACTIVE" {
                    await MainActor.run {
                        // Only notify UI when recovering from INACTIVE — not on every periodic ACTIVE heartbeat.
                        let wasAwaitingReactivation = self.isAwaitingActiveStatus
                        self.isAwaitingActiveStatus = false
                        if wasAwaitingReactivation {
                            print("💓 Heartbeat screenStatus ACTIVE — reactivating (was INACTIVE)")
                            NotificationCenter.default.post(name: .heartbeatScreenStatusActive, object: nil)
                        }
                    }
                    return .active(body)
                }

                // INACTIVE → Screen Deactivated (keep credentials/cache, wait for ACTIVE).
                if screenStatus == "INACTIVE" {
                    await MainActor.run {
                        self.isAwaitingActiveStatus = true
                        print("💓 Heartbeat screenStatus INACTIVE — Screen Deactivated (cache kept, waiting for ACTIVE)")
                        NotificationCenter.default.post(name: .screenDidDeactivate, object: nil)
                    }
                    return .inactive(body)
                }

                // DELETED → Screen Inactivated (clear credentials/cache).
                if screenStatus == "DELETED" {
                    await MainActor.run {
                        self.isAwaitingActiveStatus = false
                        print("💓 Heartbeat screenStatus DELETED — Screen Inactivated")
                        NotificationCenter.default.post(name: .screenDidInactivate, object: nil)
                    }
                    return .deleted(body)
                }

                print("⚠️ Heartbeat screenStatus '\(body?.screenStatus ?? "nil")' — not ACTIVE")
                return .requestFailed
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

    /// Apply logo/ticker from heartbeat at runtime.
    /// - non-empty → show/update immediately
    /// - explicit empty string → clear
    /// - null / omitted → leave cache unchanged (so periodic heartbeats don't wipe the ticker)
    @MainActor
    private func applyHeartbeatOverlayConfig(from data: HeartbeatResponseData?) {
        guard let data else { return }

        let previousTicker = AppRootViewModel.getSavedTickerMessage()
        let previousLogo = AppRootViewModel.getSavedLogoUrl()

        if let ticker = data.tickerMessage {
            AppRootViewModel.updateTickerMessage(ticker)
        }
        if let logo = data.logoUrl {
            AppRootViewModel.updateLogoUrl(logo)
        }

        let newTicker = AppRootViewModel.getSavedTickerMessage()
        let newLogo = AppRootViewModel.getSavedLogoUrl()
        let tickerChanged = newTicker != previousTicker
        let logoChanged = newLogo != previousLogo
        let hasLogoToReload = !(newLogo ?? "").isEmpty

        guard tickerChanged || logoChanged || hasLogoToReload else { return }

        NotificationCenter.default.post(name: .tickerUpdated, object: nil)
        print("📢 Heartbeat overlay updated (ticker=\(newTicker ?? "unchanged/cleared"), logo=\(newLogo ?? "unchanged/cleared"))")
    }
}
