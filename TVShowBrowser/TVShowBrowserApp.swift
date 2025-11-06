//
//  TVShowBrowserApp.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 07/10/25.
//

import SwiftUI

@main
struct TVShowBrowserApp: App {
    @StateObject private var listVM = AdListViewModel()
    
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
//            ContentView()
//            AdListView()
            VStack {
                        AdPlayerView(listVM: listVM)
                    .ignoresSafeArea()
                    .scaledToFill()
//                            .frame(height: 400)
//                            .cornerRadius(16)
//                            .shadow(radius: 10)
//                            .padding()
//                        
//                        Spacer()
                    }
                    .onAppear {
                        listVM.fetchAds(screenId: "174", reqNum: 1)
                    }
        }
    }
}
