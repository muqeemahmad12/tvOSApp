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
    
    /// When true, ActivationView should show Activation Failed (set when heartbeat returns INACTIVE while on player).
    @Published var showActivationFailedFromHeartbeat = false
    
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

    /// Persist the latest `secureKey` from the activation poll API.
    static func updateSecureKey(_ secureKey: String?) {
        let trimmed = secureKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        let previous = UserDefaults.standard.string(forKey: secureKeyKey)
        UserDefaults.standard.set(trimmed, forKey: secureKeyKey)
        if previous != trimmed {
            print("🔑 secureKey updated from poll (was \(previous ?? "nil"), now \(trimmed))")
        } else {
            print("🔑 secureKey from poll unchanged")
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
    /// - non-empty → cache it
    /// - empty string → remove from cache (facility no longer wants a ticker)
    /// - nil / omitted → leave cache unchanged
    static func updateTickerMessage(_ message: String?) {
        guard let message else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    /// Update logo from API:
    /// - non-empty → cache it
    /// - empty string → remove from cache (facility no longer wants a logo)
    /// - nil / omitted → leave cache unchanged
    static func updateLogoUrl(_ url: String?) {
        guard let url else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
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
        print("🖼️ Logo URL updated")
    }
    
    /// Called when heartbeat response has screenStatus INACTIVE. If we're on player, clear activation and switch to activation + show failed screen; if already on registration, do nothing.
    func handleHeartbeatScreenStatusInactive() {
        guard phase == .playing else {
            print("💓 Heartbeat INACTIVE ignored (already on activation, phase=\(phase))")
            return
        }
        print("💓 Heartbeat INACTIVE: clearing activation, switching to Activation Failed")
        Self.clearActivation()
        showActivationFailedFromHeartbeat = true
        phase = .activating
    }
    
    /// Clear activation credentials (for re-activation). Ticker message and logo are never cleared.
    static func clearActivation() {
        UserDefaults.standard.removeObject(forKey: secureKeyKey)
        UserDefaults.standard.removeObject(forKey: deviceCodeKey)
        // Intentionally keep tickerMessageKey + logoUrlKey until a later request updates them.
        print("🗑️ Activation credentials cleared (ticker/logo cache kept)")
        SentryService.shared.clearUser()
        SentryService.shared.track(SentryAnalyticsEvent.activationCleared)
        SentryService.shared.breadcrumb(category: "activation", message: "credentials_cleared", data: [:])
    }
}


