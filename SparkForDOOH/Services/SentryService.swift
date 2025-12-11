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
    /// Uses a compile-time DSN for now so integration is reliable even if
    /// Info.plist-based configuration is misaligned. You can later move the
    /// DSN and environment into `AppConfig` or build settings again.
    func start() {
        #if canImport(Sentry)
        // TODO: if desired, move this DSN back to Info.plist / AppConfig once stable.
        let dsn = "https://c353fdf8cb6dc0e392e953bd771f6260@o4510509371228160.ingest.us.sentry.io/4510509381582848"

        #if DEBUG
        let environment = "Dev"
        #else
        let environment = "Prod"
        #endif

        guard !dsn.isEmpty else {
            print("ℹ️ Sentry DSN is empty; skipping initialisation")
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = true                    // helpful while testing
            options.tracesSampleRate = 0.1          // Adjust sampling as needed
            options.enableAutoSessionTracking = true
            options.environment = environment
            
            // CRITICAL: Explicitly enable crash reporting
            // Crash reporting should be enabled by default, but let's make sure
            // The crash integration is installed automatically, but we need to ensure
            // it's properly configured for tvOS
            
            // Log when events are being sent (this helps debug)
            options.beforeSend = { event in
                if let message = event.message {
                    print("📤 Sentry sending event: \(message.formatted)")
                } else if let exception = event.exceptions?.first {
                    print("📤 Sentry sending crash: \(exception.type ?? "unknown") - \(exception.value ?? "no value")")
                } else {
                    print("📤 Sentry sending event: type=\(event.type ?? "unknown"), level=\(event.level)")
                }
                return event
            }
        }
        
        // Note: SentryCrash integration should be installed automatically
        // Check the console logs above for "Integration installed: SentryCrashIntegration"
        // If you don't see that, crash reporting may not be working

        print("✅ Sentry initialised (env=\(environment))")
        
        // After initialization, check if crash integration is active
        #if canImport(Sentry)
        // The crash integration should be installed automatically
        // Check Sentry debug logs for: "Integration installed: SentryCrashIntegration"
        print("🔍 Check console above for 'SentryCrashIntegration' - it should be installed")
        #endif
        #else
        // Sentry SDK not linked; nothing to do.
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


