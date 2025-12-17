//
//  SparkForDOOHApp.swift
//  SparkForDOOH
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI

@main
struct SparkForDOOHApp: App {
    init() {
        print("🚀 App launching...")
        
        // Initialize Sentry for crash reporting
        SentryService.shared.start()
        
        // Clear old cache after a delay (protects Sentry and AdsCache)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            FileManagerHelper.shared.clearAppStorage()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
