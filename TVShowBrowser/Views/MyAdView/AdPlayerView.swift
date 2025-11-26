//
//  AdPlayerView.swift
//  TVShowBrowser
//
//  Created by Muqeem Ahmad on 03/11/25.
//

import SwiftUI
import AVKit

struct AdPlayerView: View {
    @StateObject private var viewModel = AdPlayerViewModelNew()
    @ObservedObject var listVM: AdListViewModel
    @State private var videoFullScreen = false

    var body: some View {
        ZStack {
            if viewModel.isPreloading {
                ZStack {
                    Image("placeholder_image")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    // TOP-CENTER 2-LINE TEXT
                    VStack {
                        Text("Loading Informational Sparks \n for your clinical display")
                            .font(.system(size: 90))   // LARGE + BOLD
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(hex: "#138bcc"))   // your color code
                            .padding(.top, 50)
                        
                        Text("Your display will start automatically once the initial download is complete.")
                            .font(.system(size: 30))   // LARGE + BOLD
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(hex: "#505050"))   // your color code
                        
                        Spacer()
                    }
                    
                    // Bottom-Right Image
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image("tv_frame")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 1050)   // adjust as needed
                                .padding(.trailing, 35)
                                .padding(.bottom, 10)
                        }
                    }
//                    ProgressView(value: viewModel.preloadProgress) {
//                        Text("Preloading assets...")
//                    }
//                    .padding()
                }
            } else if let group = viewModel.currentGroup {
                GeometryReader { geo in
                    let videos = group.ii.filter { $0.assettype.lowercased() == "video" }
                    let images = group.ii.filter { $0.assettype.lowercased() == "image" }
                
                    let hasVideo = !videos.isEmpty
                    let hasImages = !images.isEmpty
                    
                    let screenWidth = geo.size.width
                    let screenHeight = geo.size.height
                    let videoWidth = hasImages ? screenWidth * 0.7 : screenWidth
                    let videoHeight = hasImages ? videoWidth * 9 / 16 : screenHeight
                    let bottomImageHeight = screenHeight - videoHeight
                    let rightImageWidth = screenWidth - videoWidth
                    
                    if hasImages && !hasVideo && images.count == 1 {
                        if let img = viewModel.imageCache[images[0].itemurl] {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        ZStack(alignment: .topLeading) {
                            // MARK: - Video Player
                            if let _ = group.ii.first(where: { $0.assettype.lowercased() == "video" }) {
                                VideoPlayer(player: viewModel.activePlayer)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(width: videoWidth, height: videoHeight)
                                    .clipped()
                                    .position(x: videoWidth / 2,
                                              y: hasImages ? (videoHeight / 2) : screenHeight / 2)
                                    .animation(.easeInOut(duration: 1.0), value: hasImages)
                            }
                            
                            // MARK: - Bottom Image
                            if let bottomAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).first {
                                if let img = viewModel.imageCache[bottomAd.itemurl] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: videoWidth, height: bottomImageHeight)
                                        .clipped()
                                        .position(x: videoWidth / 2,
                                                  y: screenHeight - bottomImageHeight / 2)
                                }
                            }
                            
                            // MARK: - Right Vertical Image (20% width)
                            if let rightAd = group.ii.filter({ $0.assettype.lowercased() == "image" }).last {
                                if let img = viewModel.imageCache[rightAd.itemurl] {
                                    Image(uiImage: img)
                                    //                                    .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: (screenWidth - videoWidth),
                                               height: screenHeight)
                                        .clipped()
                                        .position(x: videoWidth + (rightImageWidth / 2),
                                                  y: screenHeight / 2)
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.8), value: viewModel.slideOffset)
                .offset(x: viewModel.slideOffset)
            } else {
                ZStack {
                    Image("placeholder_image")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    // TOP-CENTER 2-LINE TEXT
                    VStack {
                        Text("Loading Informational Sparks \n for your clinical display")
                            .font(.system(size: 90))   // LARGE + BOLD
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(hex: "#138bcc"))   // your color code
                            .padding(.top, 50)
                        
                        Text("Your display will start automatically once the initial download is complete.")
                            .font(.system(size: 30))   // LARGE + BOLD
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(hex: "#505050"))   // your color code
//                            .padding(.top, 5)
                        
                        Spacer()
                    }
                    
                    // Bottom-Right Image
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image("tv_frame")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 1050)   // adjust as needed
                                .padding(.trailing, 35)
                                .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        // MARK: - ViewModel Triggers
        .onChange(of: listVM.groupedAds) { newGroups in
            if !newGroups.isEmpty {
                viewModel.startPlayback(with: newGroups)
            }
        }
        .onAppear {
            if !listVM.groupedAds.isEmpty {
                viewModel.startPlayback(with: listVM.groupedAds)
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
