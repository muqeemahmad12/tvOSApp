//
//  SparkForDOOHApp.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI
#if canImport(Sentry)
import Sentry
#endif
import Darwin

@main
struct SparkForDOOHApp: App {
    init() {
        // CRITICAL: Initialize Sentry FIRST so it can send any pending crash reports
        // from the previous run before we clear storage.
        print("🚀 App launching - initializing Sentry...")
        SentryService.shared.start()
        
        // IMPORTANT: On the launch AFTER a crash, Sentry needs time to:
        // 1. Detect the crash report
        // 2. Process it
        // 3. Send it to the server
        // We'll wait 15 seconds to be safe, then check if it was sent
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            #if canImport(Sentry)
            print("⏰ 15 seconds elapsed - checking Sentry status...")
            
            // Check SentryCrash directory for crash reports
            if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let sentryDir = cacheDir.appendingPathComponent("io.sentry")
                if FileManager.default.fileExists(atPath: sentryDir.path) {
                    print("📁 Checking SentryCrash directory: \(sentryDir.path)")
                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: sentryDir.path) {
                        print("📂 Sentry directory contents: \(contents)")
                        for item in contents {
                            let itemPath = sentryDir.appendingPathComponent(item)
                            if let subContents = try? FileManager.default.contentsOfDirectory(atPath: itemPath.path) {
                                print("  📂 \(item)/ contains: \(subContents)")
                                // Look for crash reports (check all files, not just those with "crash" in name)
                                for subItem in subContents {
                                    let fullPath = itemPath.appendingPathComponent(subItem)
                                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath.path),
                                       let fileSize = attrs[.size] as? Int64 {
                                        // Check if file might be a crash report (larger than 1KB, not a .state file)
                                        if !subItem.hasSuffix(".state") && fileSize > 1024 {
                                            print("  🚨 Potential crash report: \(subItem) (\(fileSize) bytes)")
                                        }
                                    }
                                    // Also check for files with "crash", "report", or "Recrash" in name
                                    let lowerName = subItem.lowercased()
                                    if lowerName.contains("crash") || lowerName.contains("report") || lowerName.contains("recrash") {
                                        print("  🚨 Found crash-related file: \(subItem)")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    print("⚠️ Sentry directory does not exist: \(sentryDir.path)")
                }
            }
            
            // Explicitly flush Sentry to ensure all pending events are sent
            SentrySDK.flush(timeout: 10)
            print("🔄 Sentry flush completed")
            #endif
            
            let fileHelper = FileManagerHelper.shared
            
            // 1️⃣ Before clear
            let sizeBefore = fileHelper.totalAppStorageSize()
            print("📦 App storage before clear: \(ByteCountFormatter.string(fromByteCount: Int64(sizeBefore), countStyle: .file))")
            
            // 2️⃣ Clear both directories (Sentry's crash data is protected)
            fileHelper.clearAppStorage()
            
            // 3️⃣ After clear
            let sizeAfter = fileHelper.totalAppStorageSize()
            print("📦 App storage after clear: \(ByteCountFormatter.string(fromByteCount: Int64(sizeAfter), countStyle: .file))")
        }

        // MARK: - Intentional Crash for Testing (DISABLED)
        // NOTE: Native crash reporting on tvOS has limitations:
        // - WatchdogTermination tracking works (detects app terminations)
        // - App hang detection works
        // - Session tracking works
        // - Error/message capture works
        // - Native crash reports (SentryCrash) may not work reliably on tvOS
        //
        // To test crash reporting, uncomment the block below and run WITHOUT debugger:
        // 1. Build from Xcode (Cmd+R)
        // 2. Stop the app (Cmd+.)
        // 3. Close Xcode completely
        // 4. Launch app from Apple TV home screen
        // 5. Wait for crash, then relaunch to send report
        /*
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("💥 Triggering intentional crash for Sentry testing...")
            #if canImport(Sentry)
            SentrySDK.addBreadcrumb(Breadcrumb(level: .error, category: "test"))
            SentrySDK.capture(message: "About to crash for testing")
            SentrySDK.setUser(User(userId: "test-crash-user"))
            SentrySDK.flush(timeout: 1)
            abort() // SIGABRT native crash
            #endif
        }
        #endif
        */
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
