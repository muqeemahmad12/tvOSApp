//
//  SentryService.swift
//  SparkForDOOH
//
//  Lightweight wrapper around Sentry crash/error reporting.
//  Compiles even when the Sentry SDK is not linked; enable via SwiftPM when ready.
//

import Foundation

#if canImport(Sentry)
import Sentry
#endif

final class SentryService {
    static let shared = SentryService()

    private init() {}

    /// Initialise Sentry for crash/error reporting.
    /// DSN and environment are read from AppConfig (which pulls from xcconfig files).
    func start() {
        #if canImport(Sentry)
        let config = AppConfig.current
        let dsn = config.sentryDSN.isEmpty
            ? "https://c353fdf8cb6dc0e392e953bd771f6260@o4510509371228160.ingest.us.sentry.io/4510509381582848"
            : config.sentryDSN
        let environment = config.environment

        guard !dsn.isEmpty else {
            print("ℹ️ Sentry DSN is empty; skipping initialisation")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false  // Set to true for debugging
            options.tracesSampleRate = 0.1
            options.enableAutoSessionTracking = true
            options.environment = environment
            
            options.beforeSend = { event in
                if let message = event.message {
                    print("📤 Sentry sending event: \(message.formatted)")
                } else if let exception = event.exceptions?.first {
                    print("📤 Sentry sending crash: \(exception.type ?? "unknown") - \(exception.value ?? "no value")")
                }
                return event
            }
        }

        print("✅ Sentry initialised (env=\(environment))")
        #endif
    }

    /// Capture an error explicitly (optional helper).
    func capture(error: Error) {
        #if canImport(Sentry)
        SentrySDK.capture(error: error)
        #else
        // No-op if Sentry is not available.
        #endif
    }
}


