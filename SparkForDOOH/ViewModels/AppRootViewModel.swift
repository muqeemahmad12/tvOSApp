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
    
    // Keys for UserDefaults persistence
    private static let isActivatedKey = "com.doceree.sparkfordooh.isActivated"
    private static let secureKeyKey = "com.doceree.sparkfordooh.secureKey"
    private static let deviceCodeKey = "com.doceree.sparkfordooh.deviceCode"
    
    init() {
        // Check if device was previously activated
        if Self.isDeviceActivated() {
            print("✅ Device previously activated - skipping activation screen")
            self.phase = .playing
        } else {
            self.phase = .activating
        }
    }
    
    // MARK: - Persistence Methods
    
    /// Check if device has been activated before
    static func isDeviceActivated() -> Bool {
        return UserDefaults.standard.bool(forKey: isActivatedKey)
    }
    
    /// Save activation state when device is activated
    static func saveActivation(secureKey: String?, deviceCode: String?) {
        UserDefaults.standard.set(true, forKey: isActivatedKey)
        if let secureKey = secureKey {
            UserDefaults.standard.set(secureKey, forKey: secureKeyKey)
        }
        if let deviceCode = deviceCode {
            UserDefaults.standard.set(deviceCode, forKey: deviceCodeKey)
        }
        print("💾 Activation saved to UserDefaults")
    }
    
    /// Get saved secure key
    static func getSavedSecureKey() -> String? {
        return UserDefaults.standard.string(forKey: secureKeyKey)
    }
    
    /// Get saved device code
    static func getSavedDeviceCode() -> String? {
        return UserDefaults.standard.string(forKey: deviceCodeKey)
    }
    
    /// Clear activation (for testing or re-activation)
    static func clearActivation() {
        UserDefaults.standard.removeObject(forKey: isActivatedKey)
        UserDefaults.standard.removeObject(forKey: secureKeyKey)
        UserDefaults.standard.removeObject(forKey: deviceCodeKey)
        print("🗑️ Activation cleared from UserDefaults")
    }
}


