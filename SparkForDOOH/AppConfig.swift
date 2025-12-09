//
//  AppConfig.swift
//  SparkForDOOH
//
//  Central place for environment-specific configuration.
//

import Foundation

/// Centralised configuration for environment-specific values (URLs, screenId, timing).
/// Values are primarily sourced from `Info.plist` / build settings and fall back
/// to sensible QA defaults when not provided.
struct AppConfig {
    static let current = AppConfig()

    /// Base URL for DRS / playlist APIs.
    let drsBaseURL: URL

    /// Base URL for activation / polling APIs.
    let activationBaseURL: URL

    /// Screen identifier used to fetch playlists for this device.
    let screenId: String

    /// Interval (seconds) after which the playlist auto-sync repeats.
    let playlistRepeatInterval: TimeInterval

    /// Delay (seconds) before auto-advancing from activation to player in test mode.
    let activationTestTransitionDelay: TimeInterval

    /// When true, activation view will auto-advance after `activationTestTransitionDelay`
    /// even if the backend has not yet marked the device as activated. Intended for QA/dev only.
    let activationAutoAdvanceForDebug: Bool

    init(
        drsBaseURL: URL? = nil,
        activationBaseURL: URL? = nil,
        screenId: String? = nil,
        playlistRepeatInterval: TimeInterval = 2 * 60,
        activationTestTransitionDelay: TimeInterval = 10,
        activationAutoAdvanceForDebug: Bool = false
    ) {
        // Prefer values injected via Info.plist / build settings, with sensible fallbacks.
        self.drsBaseURL = drsBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "DRS_BASE_URL")
            ?? URL(string: "https://qa-drs-service.doceree.com")!

        self.activationBaseURL = activationBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "ACTIVATION_BASE_URL")
            ?? URL(string: "https://dev-keen.doceree.com")!

        self.screenId = screenId
            ?? AppConfig.stringFromInfoPlist(key: "SCREEN_ID")
            ?? "174"

        self.playlistRepeatInterval = playlistRepeatInterval
        self.activationTestTransitionDelay = activationTestTransitionDelay
        self.activationAutoAdvanceForDebug = activationAutoAdvanceForDebug
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