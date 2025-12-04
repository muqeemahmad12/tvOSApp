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
        let fileHelper = FileManagerHelper.shared
        
        // 1️⃣ Before clear
        let sizeBefore = fileHelper.totalAppStorageSize()
        print("📦 App storage before clear: \(ByteCountFormatter.string(fromByteCount: Int64(sizeBefore), countStyle: .file))")
        
        // 2️⃣ Clear both directories
        fileHelper.clearAppStorage()
        
        // 3️⃣ After clear
        let sizeAfter = fileHelper.totalAppStorageSize()
        print("📦 App storage after clear: \(ByteCountFormatter.string(fromByteCount: Int64(sizeAfter), countStyle: .file))")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
