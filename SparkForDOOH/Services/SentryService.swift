//
//  SentryService.swift
//  SparkForDOOH
//
//  Crash reporting + product analytics via Sentry (sessions, user, breadcrumbs, info events).
//

import Darwin
import Foundation

#if canImport(Sentry)
import Sentry
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Namespaced analytics event names (appear as Sentry messages / Discover filters).
enum SentryAnalyticsEvent {
    /// Process start + tv-config fetched + Sentry initialised and device scope attached (one per cold start of this sequence).
    static let appLaunch = "app.lifecycle.launch"
    static let initialHeartbeatSuccess = "app.heartbeat.initial_success"
    static let initialHeartbeatFailed = "app.heartbeat.initial_failed"
    static let activationSaved = "app.activation.saved"
    static let activationCleared = "app.activation.cleared"
    static let playlistLoaded = "app.playlist.loaded"
    static let playlistEmpty = "app.playlist.empty_response"
    static let playlistFetchFailed = "app.playlist.fetch_failed"
    static let playlistUsedCache = "app.playlist.used_cache_fallback"
    /// DOOH screen entered ad playback phase (activation complete or restored session).
    static let screenPlayingPhase = "app.screen.playing_phase"
    /// User-facing activation / QR pairing flow is visible.
    static let screenActivationFlow = "app.screen.activation_flow"
    /// First real content group is playing.
    static let playbackStarted = "app.playback.started"
    /// Playback torn down (e.g. leaving player).
    static let playbackStopped = "app.playback.stopped"
    /// Third-party impression trackers fired; sampled in player to limit quota.
    static let adImpression = "app.ad.impression"
    static let errorScreenActivationFailed = "app.error_screen.activation_failed"
    static let errorScreenConnectionLost = "app.error_screen.connection_lost"
    static let errorScreenWaitingForContent = "app.error_screen.waiting_for_content"
    static let networkConnectivityLost = "app.network.connectivity_lost"
    static let networkConnectivityRestored = "app.network.connectivity_restored"
}

#if canImport(Sentry) && canImport(UIKit)
/// Hardware + display metadata for Sentry tags and the `device` context (UIKit must run on MainActor).
private enum SentryDeviceMetadata {
    /// e.g. `AppleTV14,1` from sysctl `hw.model`.
    static func hardwareModelIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        var used = size
        guard sysctlbyname("hw.model", &buffer, &used, nil, 0) == 0 else {
            return "unknown"
        }
        return String(cString: buffer)
    }

    @MainActor
    static func collect() -> [String: String] {
        let machine = hardwareModelIdentifier()
        let device = UIDevice.current
        let screen = UIScreen.main
        let bounds = screen.bounds
        let native = screen.nativeBounds
        let scale = screen.nativeScale
        return [
            "platform": "tvOS",
            "os_version": device.systemVersion,
            "device_marketing_model": device.model,
            "device_machine": machine,
            "screen_points": "\(Int(bounds.width))x\(Int(bounds.height))",
            "screen_native_px": "\(Int(native.width))x\(Int(native.height))",
            "native_scale": String(format: "%.2f", scale)
        ]
    }
}
#endif

final class SentryService {
    static let shared = SentryService()

    private struct PendingTrack {
        let event: String
        let attributes: [String: String]
        let sampleRate: Double
    }
    private enum LaunchState {
        case notSent
        case sending
        case sent
    }
    private let analyticsLock = NSLock()
    private var launchState: LaunchState = .notSent
    private var pendingTracks: [PendingTrack] = []

    private init() {}

    /// After tv-config: environment tag = activation URL host.
    func start() {
        #if canImport(Sentry)
        let config = AppConfig.current
        let dsn = config.sentryDSN.isEmpty
            ? "https://fb67b94950cc30fff47b2e75ad7b65c0@o4511228284764161.ingest.us.sentry.io/4511228286402560"
            : config.sentryDSN
        let environment = TVRemoteConfigStore.shared.environmentLabel

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.environment = environment
            options.sendDefaultPii = false
            options.attachStacktrace = true
            options.enableAutoSessionTracking = true
            options.tracesSampleRate = 0.2
            options.enableAppHangTracking = true

            let bundleId = Bundle.main.bundleIdentifier ?? "com.doceree.sparkdooh.tvos"
            let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            options.releaseName = "\(bundleId)@\(shortVersion)+\(build)"
            options.dist = build

            options.onCrashedLastRun = { event in
                let summary: String
                if let message = event.message {
                    summary = message.formatted
                } else if let exception = event.exceptions?.first {
                    summary = "\(exception.type ?? "exception"): \(exception.value ?? "")"
                } else {
                    summary = "(no message)"
                }
                print("⚠️ Sentry: previous run crashed — \(summary)")
            }

            options.beforeSend = { event in
                if let message = event.message {
                    print("📤 Sentry sending event: \(message.formatted)")
                } else if let exception = event.exceptions?.first {
                    print("📤 Sentry sending crash: \(exception.type ?? "unknown") - \(exception.value ?? "no value")")
                }
                return event
            }
        }

        configureScopeTags(environment: environment)
        print("✅ Sentry initialised (env=\(environment))")
        #endif
    }

    #if canImport(Sentry)
    private func configureScopeTags(environment: String) {
        SentrySDK.configureScope { scope in
            scope.setTag(value: environment, key: "backend_host")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                scope.setTag(value: version, key: "app_version")
            }
        }
    }
    #endif

    /// Attach Apple TV hardware + screen data to every event (tags + `device` context). Call on **MainActor** after `start()`.
    @MainActor
    func attachDeviceContext(environment: String) {
        #if canImport(Sentry) && canImport(UIKit)
        guard SentrySDK.isEnabled else { return }
        var meta = SentryDeviceMetadata.collect()
        meta["backend_host"] = environment
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            meta["app_version"] = version
        }

        SentrySDK.configureScope { scope in
            scope.setTag(value: environment, key: "backend_host")
            if let v = meta["app_version"] {
                scope.setTag(value: v, key: "app_version")
            }
            scope.setTag(value: "tvOS", key: "platform")
            scope.setTag(value: meta["os_version"] ?? "", key: "os_version")
            scope.setTag(value: meta["device_machine"] ?? "", key: "device_machine")
            scope.setTag(value: meta["device_marketing_model"] ?? "", key: "device_marketing_model")
            scope.setTag(value: meta["screen_points"] ?? "", key: "screen_resolution_points")
            scope.setTag(value: meta["screen_native_px"] ?? "", key: "screen_resolution_native_px")

            let contextPayload: [String: Any] = meta.reduce(into: [:]) { $0[$1.key] = $1.value }
            scope.setContext(value: contextPayload, key: "device")
        }
        print("✅ Sentry device context: \(meta["device_machine"] ?? "?"), \(meta["screen_points"] ?? "?")")
        #endif
    }

    /// If the device was already activated, attach user + tags for crash grouping.
    /// Must run on the main actor (reads activation state via `AppRootViewModel`).
    @MainActor
    func syncUserContextIfActivated() {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        let deviceCode = AppRootViewModel.getSavedDeviceCode()
        let screenId = AppConfig.current.screenId
        if let code = deviceCode, !code.isEmpty {
            setUser(deviceCode: code, screenId: screenId)
            breadcrumb(category: "lifecycle", message: "session_restored_activated", data: [:])
        }
        #endif
    }

    /// Call after activation is persisted so crashes group per device.
    func setUser(deviceCode: String?, screenId: String? = nil) {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        if let code = deviceCode, !code.isEmpty {
            let user = User()
            user.userId = code
            SentrySDK.setUser(user)
            SentrySDK.configureScope { scope in
                scope.setTag(value: screenId ?? AppConfig.current.screenId, key: "screen_id")
            }
        } else {
            SentrySDK.setUser(nil)
        }
        #endif
    }

    func clearUser() {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        SentrySDK.setUser(nil)
        #endif
    }

    /// Trail attached to crash/error reports (cheap).
    func breadcrumb(category: String, message: String, data: [String: String] = [:]) {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        if !data.isEmpty {
            crumb.data = Dictionary(uniqueKeysWithValues: data.map { ($0.key, $0.value as Any) })
        }
        SentrySDK.addBreadcrumb(crumb)
        #endif
    }

    /// Product / funnel analytics: **info**-level message events in Sentry (Discover + Issues). Each event is also tagged `analytics_event` for filtering.
    func track(_ event: String) {
        track(event, attributes: [:], sampleRate: 1)
    }

    func track(_ event: String, attributes: [String: String]) {
        track(event, attributes: attributes, sampleRate: 1)
    }

    /// - Parameter sampleRate: `0...1`. Values `< 1` randomly skip sending to reduce Sentry quota (e.g. `0.1` ≈ one in ten).
    func track(_ event: String, attributes: [String: String], sampleRate: Double) {
        #if canImport(Sentry)
        if event != SentryAnalyticsEvent.appLaunch {
            analyticsLock.lock()
            let needsQueue = launchState != .sent
            if needsQueue {
                pendingTracks.append(PendingTrack(event: event, attributes: attributes, sampleRate: sampleRate))
            }
            analyticsLock.unlock()
            if needsQueue { return }
        }
        if event == SentryAnalyticsEvent.appLaunch {
            analyticsLock.lock()
            if launchState == .sent {
                analyticsLock.unlock()
                return
            }
            launchState = .sending
            analyticsLock.unlock()

            sendTrackNow(event, attributes: attributes, sampleRate: sampleRate)
            for item in markAppLaunchSentAndDrainQueue() {
                sendTrackNow(item.event, attributes: item.attributes, sampleRate: item.sampleRate)
            }
            return
        }
        sendTrackNow(event, attributes: attributes, sampleRate: sampleRate)
        #endif
    }

    #if canImport(Sentry)
    private func sendTrackNow(_ event: String, attributes: [String: String], sampleRate: Double) {
        guard SentrySDK.isEnabled else {
            print("⚠️ Sentry track skipped (SDK disabled): \(event)")
            return
        }
        let p = min(1, max(0, sampleRate))
        if p < 1, Double.random(in: 0..<1) >= p {
            return
        }
        SentrySDK.capture(message: event) { scope in
            scope.setLevel(.info)
            scope.setFingerprint([event])
            scope.setTag(value: event, key: "analytics_event")
            for (key, value) in attributes where key.count <= 32 && value.count <= 200 {
                scope.setTag(value: value, key: key)
            }
            if !attributes.isEmpty {
                let extras: [String: Any] = attributes.reduce(into: [:]) { $0[$1.key] = $1.value }
                scope.setContext(value: extras, key: "analytics")
            }
        }
    }

    private func markAppLaunchSentAndDrainQueue() -> [PendingTrack] {
        analyticsLock.lock()
        defer { analyticsLock.unlock() }
        if launchState == .sent {
            return []
        }
        launchState = .sent
        let queued = pendingTracks
        pendingTracks.removeAll()
        return queued
    }
    #endif

    /// Record a non-fatal error (counts toward crash-free sessions in Sentry).
    func capture(error: Error) {
        capture(error: error, tags: [:])
    }

    /// Non-fatal error with optional tags (e.g. `["layer": "playback"]`) for filtering in Issues.
    func capture(error: Error, tags: [String: String]) {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        if tags.isEmpty {
            SentrySDK.capture(error: error)
        } else {
            SentrySDK.capture(error: error) { scope in
                for (key, value) in tags where key.count <= 32 && value.count <= 200 {
                    scope.setTag(value: value, key: key)
                }
            }
        }
        #else
        #endif
    }
}

#if DEBUG
extension SentryService {
    /// Raises an uncaught `NSException` so Sentry records a **crash** sample (DEBUG only). Invoke from LLDB or a temporary DEBUG control; do not ship a user-visible trigger.
    func triggerTestCrashForPOC() {
        #if canImport(Sentry)
        NSException(
            name: NSExceptionName("SentryPOCTestCrash"),
            reason: "Intentional POC crash — validate Issues and dSYM symbolication in Sentry",
            userInfo: nil
        ).raise()
        #endif
    }
}
#endif
