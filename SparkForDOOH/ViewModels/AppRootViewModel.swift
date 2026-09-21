//
//  AppRootViewModel.swift
//  SparkForDOOH
//
//  Created by Cursor on 03/12/25.
//

import Foundation

/// High-level app phases for this kiosk-style tvOS app.
@MainActor
final class AppRootViewModel: ObservableObject {
    enum Phase {
        case activating
        case playing
    }

    @Published var phase: Phase

    /// True while heartbeat reports `INACTIVE` — show Screen Inactivated and wait for ACTIVE.
    /// Credentials and playback cache are kept.
    @Published var isScreenInactivated = false

    /// True while heartbeat reports `DELETED` — show Screen Deactivated (re-register).
    @Published var isScreenDeactivated = false

    /// Bumps when forcing a fresh activation flow so `ActivationView` remounts.
    @Published var activationSessionID = UUID()

    // Keys for UserDefaults persistence
    private static let secureKeyKey = "com.doceree.sparkfordooh.secureKey"
    private static let deviceCodeKey = "com.doceree.sparkfordooh.deviceCode"
    private static let tickerMessageKey = "com.doceree.sparkfordooh.tickerMessage"
    private static let logoUrlKey = "com.doceree.sparkfordooh.logoUrl"
    
    init() {
        // Past first-time setup only when poll secureKey exists.
        if Self.hasSavedSecureKey() {
            print("✅ secureKey present - skipping activation screen")
            self.phase = .playing
        } else {
            self.phase = .activating
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Device is past first-time setup when poll has given us a non-empty `secureKey`.
    static func hasSavedSecureKey() -> Bool {
        let key = getSavedSecureKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty
    }

    /// Check if device has been activated before (same as having a poll `secureKey`).
    static func isDeviceActivated() -> Bool {
        hasSavedSecureKey()
    }
    
    /// Save activation state when device is activated.
    /// Ticker/logo: non-empty updates cache; empty string clears that item; nil leaves it unchanged.
    static func saveActivation(secureKey: String?, deviceCode: String?, tickerMessage: String? = nil, logoUrl: String? = nil) {
        updateSecureKey(secureKey)
        if let deviceCode = deviceCode {
            UserDefaults.standard.set(deviceCode, forKey: deviceCodeKey)
        }
        updateTickerMessage(tickerMessage)
        updateLogoUrl(logoUrl)
        print("💾 Activation saved to UserDefaults (hasSecureKey=\(hasSavedSecureKey()))")
        SentryService.shared.setUser(deviceCode: deviceCode, screenId: AppConfig.current.screenId)
        SentryService.shared.track(
            SentryAnalyticsEvent.activationSaved,
            attributes: ["has_ticker": (getSavedTickerMessage()?.isEmpty == false) ? "true" : "false"]
        )
        SentryService.shared.breadcrumb(category: "activation", message: "credentials_saved", data: [:])
    }

    /// Persist the latest `secureKey` (from activation poll or heartbeat rotation).
    static func updateSecureKey(_ secureKey: String?) {
        let trimmed = secureKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        let previous = UserDefaults.standard.string(forKey: secureKeyKey)
        UserDefaults.standard.set(trimmed, forKey: secureKeyKey)
        if previous != trimmed {
            print("🔑 secureKey updated (was \(previous ?? "nil"), now \(trimmed))")
        } else {
            print("🔑 secureKey unchanged")
        }
    }
    
    /// Get saved secure key (from activation poll) — used as heartbeat/quest `x-api-key`.
    static func getSavedSecureKey() -> String? {
        return UserDefaults.standard.string(forKey: secureKeyKey)
    }
    
    /// Get saved device code
    static func getSavedDeviceCode() -> String? {
        return UserDefaults.standard.string(forKey: deviceCodeKey)
    }
    
    /// Get saved ticker message
    static func getSavedTickerMessage() -> String? {
        return UserDefaults.standard.string(forKey: tickerMessageKey)
    }
    
    /// Get saved logo URL
    static func getSavedLogoUrl() -> String? {
        return UserDefaults.standard.string(forKey: logoUrlKey)
    }
    
    /// Update ticker from API:
    /// - non-empty → cache it (newlines collapsed to spaces — always one line)
    /// - empty string → remove from cache (facility no longer wants a ticker)
    /// - nil / omitted → leave cache unchanged
    static func updateTickerMessage(_ message: String?) {
        guard let message else { return }
        let trimmed = Self.singleLineTicker(message)
        if trimmed.isEmpty {
            if UserDefaults.standard.object(forKey: tickerMessageKey) != nil {
                UserDefaults.standard.removeObject(forKey: tickerMessageKey)
                print("🗑️ Ticker cleared — empty value from API")
            }
            return
        }
        let previous = UserDefaults.standard.string(forKey: tickerMessageKey)
        guard previous != trimmed else { return }
        UserDefaults.standard.set(trimmed, forKey: tickerMessageKey)
        print("📢 Ticker updated")
    }

    /// Collapse `\r` / `\n` (and escaped variants) so ticker is always one scrolling line.
    static func singleLineTicker(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\r\\n", with: " ")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Update logo from API:
    /// - non-empty → cache it (JSON `\/` escapes normalized)
    /// - empty string → remove from cache (facility no longer wants a logo)
    /// - nil / omitted → leave cache unchanged
    static func updateLogoUrl(_ url: String?) {
        guard let url else { return }
        let trimmed = Self.normalizedLogoURLString(url)
        if trimmed.isEmpty {
            if UserDefaults.standard.object(forKey: logoUrlKey) != nil {
                UserDefaults.standard.removeObject(forKey: logoUrlKey)
                print("🗑️ Logo cleared — empty value from API")
            }
            return
        }
        let previous = UserDefaults.standard.string(forKey: logoUrlKey)
        guard previous != trimmed else { return }
        UserDefaults.standard.set(trimmed, forKey: logoUrlKey)
        print("🖼️ Logo URL updated: \(trimmed)")
    }

    /// Normalize heartbeat/activation logo URLs (`https:\/\/...` → `https://...`).
    static func normalizedLogoURLString(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
        }
        s = s.replacingOccurrences(of: "\\/", with: "/")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Handle heartbeat `INACTIVE` — show Screen Inactivated; keep credentials, playlist cache, and heartbeat until ACTIVE.
    func handleScreenInactivation() {
        guard !isScreenInactivated else { return }
        guard !isScreenDeactivated else { return }
        print("💓 Heartbeat INACTIVE — Screen Inactivated (cache kept, waiting for ACTIVE)")
        isScreenInactivated = true
        HeartbeatAPI.shared.startHeartbeat()
    }

    /// Heartbeat ACTIVE after INACTIVE — dismiss overlay; caller resumes ads and hits quest once.
    func handleScreenReactivation() {
        guard isScreenInactivated else { return }
        print("💓 Heartbeat ACTIVE — leaving Screen Inactivated, resume playlist + one quest fetch")
        isScreenInactivated = false
        if phase == .activating {
            phase = .playing
        }
    }

    /// Handle heartbeat `DELETED` — show Screen Deactivated; clear credentials + caches.
    func handleScreenDeactivation() {
        guard !isScreenDeactivated else { return }
        print("🔒 Heartbeat DELETED — Screen Deactivated (credentials/caches cleared)")
        isScreenInactivated = false
        isScreenDeactivated = true
        Self.clearActivationCredentials()
        Self.clearPlaybackCaches()
        Self.updateTickerMessage("")
        Self.updateLogoUrl("")
        HeartbeatAPI.shared.stopHeartbeat()
        HeartbeatAPI.shared.resetInitialHeartbeatGate()
    }

    /// Clear secureKey + deviceCode so the device can re-register / re-login.
    static func clearActivationCredentials() {
        UserDefaults.standard.removeObject(forKey: secureKeyKey)
        UserDefaults.standard.removeObject(forKey: deviceCodeKey)
        print("🗑️ Activation credentials cleared (re-register)")
        SentryService.shared.clearUser()
        SentryService.shared.track(SentryAnalyticsEvent.activationCleared)
        SentryService.shared.breadcrumb(category: "activation", message: "credentials_cleared_for_reregister", data: [:])
    }

    /// Kept for compatibility; deactivation no longer clears playback caches.
    static func clearPlaybackCaches() {
        PlaylistCacheService.shared.clearCache()
        FileManagerHelper.shared.clearAdsCache()
        NotificationCenter.default.post(name: .playbackCachesClearedOnDeactivation, object: nil)
        print("🗑️ Playback caches cleared (playlist + AdsCache)")
    }
}
