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
    
    var body: some Scene {
        WindowGroup {
//            ContentView()
//            AdListView()
            VStack {
                        AdPlayerView(listVM: listVM)
//                            .frame(height: 400)
//                            .cornerRadius(16)
//                            .shadow(radius: 10)
//                            .padding()
//                        
//                        Spacer()
                    }
                    .onAppear {
                        listVM.fetchAds(screenId: "123")
                    }
        }
    }
}
