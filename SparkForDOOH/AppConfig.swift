//
//  AppConfig.swift
//  SparkForDOOH
//
//  Central place for environment-specific configuration.
//

import Foundation

/// Centralised configuration for environment-specific values (URLs, screenId, timing).
/// Values are primarily sourced from `Info.plist` / build settings (via .xcconfig files)
/// and fall back to sensible QA defaults when not provided.
///
/// To configure for different environments:
/// 1. Set the xcconfig file in Xcode project settings (Dev.xcconfig, QA.xcconfig, Prod.xcconfig)
/// 2. Or create separate build schemes for each environment
struct AppConfig {
    static let current = AppConfig()

    /// Current environment name (Dev, QA, Prod).
    let environment: String
    
    /// Base URL for DRS / playlist APIs.
    let drsBaseURL: URL

    /// Base URL for activation / polling APIs.
    let activationBaseURL: URL
    
    /// Base URL for Spark portal (QR code / activation website).
    let sparkPortalURL: URL

    /// Screen identifier used to fetch playlists for this device.
    let screenId: String
    
    /// Sentry DSN for crash reporting.
    let sentryDSN: String

    /// Interval (seconds) after which the playlist auto-sync repeats.
    let playlistRepeatInterval: TimeInterval

    /// Delay (seconds) before auto-advancing from activation to player in test mode.
    let activationTestTransitionDelay: TimeInterval

    /// When true, activation view will auto-advance after `activationTestTransitionDelay`
    /// even if the backend has not yet marked the device as activated. Intended for QA/dev only.
    let activationAutoAdvanceForDebug: Bool

    init(
        environment: String? = nil,
        drsBaseURL: URL? = nil,
        activationBaseURL: URL? = nil,
        sparkPortalURL: URL? = nil,
        screenId: String? = nil,
        sentryDSN: String? = nil,
        playlistRepeatInterval: TimeInterval = 2 * 60,
        activationTestTransitionDelay: TimeInterval = 10,
        activationAutoAdvanceForDebug: Bool = false
    ) {
        // Environment name from xcconfig (defaults to QA)
        self.environment = environment
            ?? AppConfig.stringFromInfoPlist(key: "ENVIRONMENT")
            ?? "QA"
        
        // Prefer values injected via Info.plist / build settings, with QA fallbacks.
        self.drsBaseURL = drsBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "DRS_BASE_URL")
            ?? URL(string: "https://qa-drs-service.doceree.com")!

        self.activationBaseURL = activationBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "ACTIVATION_BASE_URL")
            ?? URL(string: "https://qa-keen.doceree.com")!
        
        self.sparkPortalURL = sparkPortalURL
            ?? AppConfig.urlFromInfoPlist(key: "SPARK_PORTAL_URL")
            ?? URL(string: "https://qa-spark.doceree.com")!

        self.screenId = screenId
            ?? AppConfig.stringFromInfoPlist(key: "SCREEN_ID")
            ?? "174"
        
        self.sentryDSN = sentryDSN
            ?? AppConfig.stringFromInfoPlist(key: "SENTRY_DSN")
            ?? ""

        self.playlistRepeatInterval = playlistRepeatInterval
        self.activationTestTransitionDelay = activationTestTransitionDelay
        self.activationAutoAdvanceForDebug = activationAutoAdvanceForDebug
        
        // Log current configuration
        print("📋 AppConfig loaded: environment=\(self.environment), drsBaseURL=\(self.drsBaseURL), activationBaseURL=\(self.activationBaseURL), sparkPortalURL=\(self.sparkPortalURL)")
    }

    // MARK: - Helpers

    /// Read a URL value from Info.plist using the given key.
    private static func urlFromInfoPlist(key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value),
              !value.isEmpty else {
            return nil
        }
        return url
    }

    /// Read a String value from Info.plist using the given key.
    private static func stringFromInfoPlist(key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}