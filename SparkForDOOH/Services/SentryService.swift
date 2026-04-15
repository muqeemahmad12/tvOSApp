//
//  SentryService.swift
//  SparkForDOOH
//
//  Crash reporting + product analytics via Sentry (sessions, user, breadcrumbs, info events).
//

import Foundation

#if canImport(Sentry)
import Sentry
#endif

/// Namespaced analytics event names (appear as Sentry messages / Discover filters).
enum SentryAnalyticsEvent {
    static let tvConfigLoaded = "app.tv_config.loaded"
    static let initialHeartbeatSuccess = "app.heartbeat.initial_success"
    static let initialHeartbeatFailed = "app.heartbeat.initial_failed"
    static let activationSaved = "app.activation.saved"
    static let activationCleared = "app.activation.cleared"
    static let playlistLoaded = "app.playlist.loaded"
    static let playlistEmpty = "app.playlist.empty_response"
    static let playlistFetchFailed = "app.playlist.fetch_failed"
    static let playlistUsedCache = "app.playlist.used_cache_fallback"
}

final class SentryService {
    static let shared = SentryService()

    private init() {}

    /// After tv-config: environment tag = activation URL host.
    func start() {
        #if canImport(Sentry)
        let config = AppConfig.current
        let dsn = config.sentryDSN.isEmpty
            ? "https://c353fdf8cb6dc0e392e953bd771f6260@o4510509371228160.ingest.us.sentry.io/4510509381582848"
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

    /// Product / funnel analytics: shows up in Sentry as **info** issues and in Discover (filter level=info).
    func track(_ event: String) {
        track(event, attributes: [:])
    }

    func track(_ event: String, attributes: [String: String]) {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(message: event) { scope in
            scope.setLevel(.info)
            scope.setFingerprint([event])
            for (key, value) in attributes where key.count <= 32 && value.count <= 200 {
                scope.setTag(value: value, key: key)
            }
            if !attributes.isEmpty {
                let extras: [String: Any] = attributes.reduce(into: [:]) { $0[$1.key] = $1.value }
                scope.setContext(value: extras, key: "analytics")
            }
        }
        #endif
    }

    /// Record a non-fatal error (counts toward crash-free sessions in Sentry).
    func capture(error: Error) {
        #if canImport(Sentry)
        guard SentrySDK.isEnabled else { return }
        SentrySDK.capture(error: error)
        #else
        #endif
    }
}
