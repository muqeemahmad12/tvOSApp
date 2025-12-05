//
//  AppConfig.swift
//  SparkForDOOH
//
//  Central place for environment-specific configuration.
//

import Foundation

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

    init(
        drsBaseURL: URL = URL(string: "https://qa-drs-service.doceree.com")!,
        activationBaseURL: URL = URL(string: "https://dev-keen.doceree.com")!,
        screenId: String = "174",
        playlistRepeatInterval: TimeInterval = 2 * 60,
        activationTestTransitionDelay: TimeInterval = 10
    ) {
        self.drsBaseURL = drsBaseURL
        self.activationBaseURL = activationBaseURL
        self.screenId = screenId
        self.playlistRepeatInterval = playlistRepeatInterval
        self.activationTestTransitionDelay = activationTestTransitionDelay
    }
}


