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
    private static let isActivatedKey = "com.doceree.sparkfordooh.isActivated"
    private static let secureKeyKey = "com.doceree.sparkfordooh.secureKey"
    private static let deviceCodeKey = "com.doceree.sparkfordooh.deviceCode"
    private static let tickerMessageKey = "com.doceree.sparkfordooh.tickerMessage"
    private static let logoUrlKey = "com.doceree.sparkfordooh.logoUrl"
    
    private var heartbeatInactiveObserver: NSObjectProtocol?
    
    init() {
        // Check if device was previously activated
        if Self.isDeviceActivated() {
            print("✅ Device previously activated - skipping activation screen")
            self.phase = .playing
        } else {
            self.phase = .activating
        }
        // Observe heartbeat INACTIVE on main queue so we switch to Activation Failed when on player
        heartbeatInactiveObserver = NotificationCenter.default.addObserver(
            forName: .heartbeatScreenStatusInactive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleHeartbeatScreenStatusInactive()
            }
        }
    }
    
    deinit {
        if let o = heartbeatInactiveObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Check if device has been activated before
    static func isDeviceActivated() -> Bool {
        return UserDefaults.standard.bool(forKey: isActivatedKey)
    }
    
    /// Save activation state when device is activated
    static func saveActivation(secureKey: String?, deviceCode: String?, tickerMessage: String? = nil, logoUrl: String? = nil) {
        UserDefaults.standard.set(true, forKey: isActivatedKey)
        if let secureKey = secureKey {
            UserDefaults.standard.set(secureKey, forKey: secureKeyKey)
        }
        if let deviceCode = deviceCode {
            UserDefaults.standard.set(deviceCode, forKey: deviceCodeKey)
        }
        if let tickerMessage = tickerMessage, !tickerMessage.isEmpty {
            UserDefaults.standard.set(tickerMessage, forKey: tickerMessageKey)
        }
        if let logoUrl = logoUrl, !logoUrl.isEmpty {
            UserDefaults.standard.set(logoUrl, forKey: logoUrlKey)
        }
        print("💾 Activation saved to UserDefaults")
        SentryService.shared.setUser(deviceCode: deviceCode, screenId: AppConfig.current.screenId)
        SentryService.shared.track(
            SentryAnalyticsEvent.activationSaved,
            attributes: ["has_ticker": (tickerMessage != nil && !(tickerMessage?.isEmpty ?? true)) ? "true" : "false"]
        )
        SentryService.shared.breadcrumb(category: "activation", message: "credentials_saved", data: [:])
    }
    
    /// Get saved secure key
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
    
    /// Update ticker message (can be updated during heartbeat)
    static func updateTickerMessage(_ message: String?) {
        if let message = message, !message.isEmpty {
            UserDefaults.standard.set(message, forKey: tickerMessageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tickerMessageKey)
        }
    }
    
    /// Update logo URL (can be updated during heartbeat)
    static func updateLogoUrl(_ url: String?) {
        if let url = url, !url.isEmpty {
            UserDefaults.standard.set(url, forKey: logoUrlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: logoUrlKey)
        }
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
    
    /// Clear activation (for testing or re-activation)
    static func clearActivation() {
        UserDefaults.standard.removeObject(forKey: isActivatedKey)
        UserDefaults.standard.removeObject(forKey: secureKeyKey)
        UserDefaults.standard.removeObject(forKey: deviceCodeKey)
        UserDefaults.standard.removeObject(forKey: tickerMessageKey)
        UserDefaults.standard.removeObject(forKey: logoUrlKey)
        print("🗑️ Activation cleared from UserDefaults")
        SentryService.shared.clearUser()
        SentryService.shared.track(SentryAnalyticsEvent.activationCleared)
        SentryService.shared.breadcrumb(category: "activation", message: "credentials_cleared", data: [:])
    }
}


