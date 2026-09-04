//
//  AppConfig.swift
//  SparkForDOOH
//
//  Screen id, API key, Spark portal default, Sentry DSN. API hosts come from tv-config URLs only.
//

import Foundation

struct AppConfig {
    static let current = AppConfig()

    let drsBaseURL: URL
    let activationBaseURL: URL
    let sparkPortalURL: URL
    let screenId: String
    let sentryDSN: String
    /// `x-api-key` for activation / heartbeat (Keen).
    let apiKey: String
    /// Static DRS quest key (Info.plist `DRS_QUEST_API_KEY`); not used as quest `x-api-key` (that is poll `secureKey`).
    let drsQuestApiKey: String
    let adsCacheMaxBytes: UInt64
    let playlistRepeatInterval: TimeInterval
    let activationTestTransitionDelay: TimeInterval
    let activationAutoAdvanceForDebug: Bool

    init(
        drsBaseURL: URL? = nil,
        activationBaseURL: URL? = nil,
        sparkPortalURL: URL? = nil,
        screenId: String? = nil,
        sentryDSN: String? = nil,
        apiKey: String? = nil,
        drsQuestApiKey: String? = nil,
        adsCacheMaxBytes: UInt64? = nil,
        playlistRepeatInterval: TimeInterval = 10 * 60,
        activationTestTransitionDelay: TimeInterval = 10,
        activationAutoAdvanceForDebug: Bool = false
    ) {
        self.drsBaseURL = drsBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "DRS_BASE_URL")
            ?? URL(string: "https://drs-service.doceree.com")!
        self.activationBaseURL = activationBaseURL
            ?? AppConfig.urlFromInfoPlist(key: "ACTIVATION_BASE_URL")
            ?? URL(string: "https://keen.doceree.com")!
        self.sparkPortalURL = sparkPortalURL
            ?? AppConfig.urlFromInfoPlist(key: "SPARK_PORTAL_URL")
            ?? URL(string: "https://spark.doceree.com")!
        self.screenId = screenId
            ?? AppConfig.stringFromInfoPlist(key: "SCREEN_ID")
            ?? "174"
        self.sentryDSN = sentryDSN
            ?? AppConfig.stringFromInfoPlist(key: "SENTRY_DSN")
            ?? ""
        self.apiKey = apiKey
            ?? AppConfig.stringFromInfoPlist(key: "API_KEY")
            ?? "f0172f77-966b-4be3-aef1-7fd439028a46"
        self.drsQuestApiKey = drsQuestApiKey
            ?? AppConfig.stringFromInfoPlist(key: "DRS_QUEST_API_KEY")
            ?? "fdd74745-a0ed-440c-ad10-3815d659a599"

        let cacheMaxMB: Double
        if let bytes = adsCacheMaxBytes {
            cacheMaxMB = Double(bytes) / (1024 * 1024)
        } else if let plistMB = AppConfig.numberFromInfoPlist(key: "ADS_CACHE_MAX_MB") {
            cacheMaxMB = plistMB
        } else {
            cacheMaxMB = 500
        }
        self.adsCacheMaxBytes = UInt64(cacheMaxMB * 1024 * 1024)
        self.playlistRepeatInterval = playlistRepeatInterval
        self.activationTestTransitionDelay = activationTestTransitionDelay
        self.activationAutoAdvanceForDebug = activationAutoAdvanceForDebug
    }

    private static func urlFromInfoPlist(key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), !value.isEmpty else { return nil }
        return url
    }

    private static func stringFromInfoPlist(key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func numberFromInfoPlist(key: String) -> Double? {
        if let number = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber {
            return number.doubleValue
        }
        if let string = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           let doubleValue = Double(string) {
            return doubleValue
        }
        return nil
    }
}
